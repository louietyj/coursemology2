# frozen_string_literal: true
class Course::StatisticsController < Course::ComponentController
  include Course::LessonPlan::PersonalizationConcern

  before_action :authorize_read_statistics!

  def student
    preload_levels
    course_users = current_course.course_users.includes(:groups)
    staff = course_users.staff
    all_students = course_users.students.ordered_by_experience_points.with_video_statistics
    @phantom_students, @students = all_students.partition(&:phantom?)
    @service = Course::GroupManagerPreloadService.new(staff)
    @lrs = get_lrs(all_students)
  end

  def staff
    @staffs = current_course.course_users.teaching_assistant_and_manager
    @staffs = CourseUser.order_by_average_marking_time(@staffs)
    @lrs = get_lrs(@staffs)
  end

  private

  def get_lrs(course_users)
    lrs = course_users.map do |course_user|
      items = current_course.lesson_plan_items.published.
              with_reference_times_for(course_user).
              with_personal_times_for(course_user).
              to_a
      items = items.sort_by { |x| x.time_for(course_user).start_at }
      [
        course_user.id,
        compute_learning_rate_ema(
          course_user, items.select(&:affects_personal_times?), lesson_plan_items_submission_time_hash(course_user)
        )
      ]
    end
    lrs.to_h
  end

  def authorize_read_statistics!
    authorize!(:read_statistics, current_course)
  end

  # Pre-loads course levels to avoid N+1 queries when course_user.level_numbers are displayed.
  def preload_levels
    current_course.levels.to_a
  end

  # @return [Course::StatisticsComponent]
  # @return [nil] If component is disabled.
  def component
    current_component_host[:course_statistics_component]
  end
end
