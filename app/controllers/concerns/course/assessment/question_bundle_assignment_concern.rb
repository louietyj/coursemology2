# frozen_string_literal: true
module Course::Assessment::QuestionBundleAssignmentConcern
  extend ActiveSupport::Concern

  # All validations need to present a ValidationResult of this form, which will be consumed by the view.
  # This struct is loosely inspired by Rails' model validation, but heavily extended.
  # rubocop:disable Layout/CommentIndentation
  ValidationResult = Struct.new(
    :type,              # Hard or soft
    :pass,              # Whether this should be displayed as a tick or cross on the validation summary
    :score_penalty,     # For selecting the best randomized outcome
    :info,              # For displaying additional information. Fed into I18n.
                        # E.g. { metric: 0.9 }
    :offending_cells,   # For highlighting the cell and displaying the error in a tooltip. Fed into I18n.
                        # E.g. { (student, group): { lift_error: { lift: -3 } } }
    keyword_init: true
  )
  # rubocop:enable Layout/CommentIndentation

  # Computations on a large set of QBAs are expensive, and we need a lean in-memory representation of a set of QBAs.
  #
  # An AssignmentSet is a (thin) abstraction over a set of QBAs for an assessment which assumes consistency of the
  # underlying data. The constructing code is responsible for data translation / validation.
  #
  # Essentially a nested hash of Student -> Group -> Bundle. Group is nil if assigned bundle is extraneous. Everything
  # is identified by an integer ID.
  class AssignmentSet
    attr_accessor :assignments, :group_bundles

    def initialize(students, group_bundles)
      @assignments = students.map { |x| [x, { nil => [] }] }.to_h
      @group_bundles = group_bundles
      @group_bundles_lookup = group_bundles.flat_map do |group, bundles|
        bundles.map { |bundle| [bundle, group] }
      end.to_h
    end

    def add_assignment(student, bundle)
      group = @group_bundles_lookup[bundle]
      @assignments[student] ||= { nil => [] }
      if @assignments[student][group].nil?
        @assignments[student][group] = bundle
      else
        @assignments[student][nil].append(bundle)
      end
    end
  end

  class AssignmentRandomizer
    attr_accessor :assignments, :students, :group_bundles

    def initialize(assessment)
      @assessment = assessment
      @students = assessment.course.user_ids
      @group_bundles = assessment.question_group_ids.map { |x| [x, []] }.to_h
      assessment.question_bundles.each { |bundle| @group_bundles[bundle.group_id].append(bundle.id) }
    end

    def load
      AssignmentSet.new(@students, @group_bundles).tap do |assignment_set|
        @assessment.question_bundle_assignments.where(submission: nil).each do |qba|
          assignment_set.add_assignment(qba.user_id, qba.bundle_id)
        end
      end
    end

    def save(assignment_set)
      # Deletion must be done atomically to prevent race conditions
      @assessment.question_bundle_assignments.where(submission: nil).delete_all
      new_question_bundle_assignments = []
      assignment_set.assignments.each do |student_id, assigned_group_bundles|
        assigned_group_bundles.each do |group_id, bundle_id|
          next if group_id.nil? || bundle_id.nil?

          new_question_bundle_assignments << Course::Assessment::QuestionBundleAssignment.new(
            user_id: student_id,
            assessment_id: @assessment.id,
            bundle_id: bundle_id
          )
        end
      end
      Course::Assessment::QuestionBundleAssignment.import! new_question_bundle_assignments
    end

    def randomize
      # Naive strategy: For each group, add a random bundle
      AssignmentSet.new(@students, @group_bundles).tap do |assignment_set|
        @students.each do |student|
          @group_bundles.each do |_, bundles|
            assignment_set.add_assignment(student, bundles.sample)
          end
        end
      end
    end

    def validate(assignment_set)
      [
        validate_no_overlapping_questions,
        validate_no_empty_groups,
        validate_one_bundle_assigned(assignment_set),
        validate_no_repeat_bundles(assignment_set)
      ].reduce(&:merge)
    end

    private

    def validate_no_overlapping_questions
      questions = Course::Assessment::Question.
                  where(id: @assessment.question_bundle_questions.group(:question_id).
                            having('count(*) > 1').
                            select(:question_id)).
                  pluck(:title).
                  to_sentence
      {
        no_overlapping_questions:
          ValidationResult.new(
            type: :hard,
            pass: questions.empty?,
            info: questions.empty? ? {} : { fail: { questions: questions } }
          )
      }
    end

    def validate_no_empty_groups
      groups = @assessment.question_groups.where.not(id: @assessment.question_bundles.select(:group_id)).pluck(:title).to_sentence
      {
        no_empty_groups:
          ValidationResult.new(
            type: :hard,
            pass: groups.empty?,
            info: groups.empty? ? {} : { fail: { groups: groups } }
          )
      }
    end

    def validate_one_bundle_assigned(assignment_set)
      student_ids = Set.new
      offending_cells = {}
      assignment_set.assignments.each do |student_id, assignment|
        assignment_set.group_bundles.keys.each do |group_bundle|
          if assignment[group_bundle].nil?
            student_ids << student_id
            offending_cells[[student_id, group_bundle]] = { missing_bundle: {} }
          end
        end
        if assignment[nil].present?
          student_ids << student_id
          offending_cells[[student_id, nil]] = { unbundled: {} }
        end
      end
      students = User.where(id: student_ids).pluck(:name).to_sentence
      {
        one_bundle_assigned:
          ValidationResult.new(
            type: :hard,
            pass: students.empty?,
            info: students.empty? ? {} : { fail: { students: students } },
            offending_cells: offending_cells
          )
      }
    end

    def validate_no_repeat_bundles(assignment_set)
      attempted_questions = {}
      @assessment.question_bundle_assignments.where.not(submission: nil).pluck(:user_id, :bundle_id).
        each do |user_id, bundle_id|
        attempted_questions[user_id] ||= Set.new
        attempted_questions[user_id] << bundle_id
      end
      student_ids = Set.new
      offending_cells = {}
      assignment_set.assignments.each do |student_id, assignment|
        assignment_set.group_bundles.keys.each do |group_bundle|
          if assignment[group_bundle].present? && assignment[group_bundle].in?(attempted_questions[student_id] || [])
            student_ids << student_id
            offending_cells[[student_id, group_bundle]] = { repeat_bundle: {} }
          end
        end
        if assignment[nil].present? && assignment[nil].any? { |b| b.in?(attempted_questions[student_id] || []) }
          student_ids << student_id
          offending_cells[[student_id, nil]] = { repeat_bundle: {} }
        end
      end
      students = User.where(id: student_ids).pluck(:name).to_sentence
      {
        no_repeat_bundles:
          ValidationResult.new(
            type: :hard,
            pass: students.empty?,
            info: students.empty? ? {} : { fail: { students: students } },
            offending_cells: offending_cells
          )
      }
    end
  end
end
