# frozen_string_literal: true
class Course::LessonPlan::Item < ApplicationRecord
  include Course::LessonPlan::ItemTodoConcern

  has_many :personal_times,
           foreign_key: :lesson_plan_item_id, class_name: Course::PersonalTime.name,
           inverse_of: :lesson_plan_item, dependent: :destroy, autosave: true
  has_many :reference_times,
           foreign_key: :lesson_plan_item_id, class_name: Course::ReferenceTime.name, inverse_of: :lesson_plan_item,
           dependent: :destroy, autosave: true
  has_one :default_reference_time,
          -> { joins(:reference_timeline).where(course_reference_timelines: { default: true }) },
          foreign_key: :lesson_plan_item_id, class_name: Course::ReferenceTime.name, inverse_of: :lesson_plan_item,
          autosave: true
  validates :default_reference_time, presence: true
  validate :validate_only_one_default_reference_time

  actable optional: true
  has_many_attachments on: :description

  after_initialize :set_default_reference_time, if: :new_record?
  after_initialize :set_default_values, if: :new_record?

  validate :validate_presence_of_bonus_end_at,
           :validate_start_at_cannot_be_after_end_at
  validates :base_exp, :time_bonus_exp, numericality: { greater_than_or_equal_to: 0 }
  validates :actable_type, length: { maximum: 255 }, allow_nil: true
  validates :title, length: { maximum: 255 }, presence: true
  validates :published, inclusion: { in: [true, false] }
  validates :movable, inclusion: { in: [true, false] }
  validates :triggers_recomputation, inclusion: { in: [true, false] }
  validates :base_exp, numericality: { only_integer: true, greater_than_or_equal_to: -2_147_483_648,
                                       less_than: 2_147_483_648 }, presence: true
  validates :time_bonus_exp, numericality: { only_integer: true, greater_than_or_equal_to: -2_147_483_648,
                                             less_than: 2_147_483_648 }, presence: true
  validates :closing_reminder_token, numericality: true, allow_nil: true
  validates :creator, presence: true
  validates :updater, presence: true
  validates :course, presence: true
  validates :actable_id, uniqueness: { scope: [:actable_type], allow_nil: true,
                                       if: -> { actable_type? && actable_id_changed? } }
  validates :actable_type, uniqueness: { scope: [:actable_id], allow_nil: true,
                                         if: -> { actable_id? && actable_type_changed? } }

  # @!method self.ordered_by_date
  #   Orders the lesson plan items by the starting date.
  scope :ordered_by_date, (lambda do
    includes(reference_times: :reference_timeline).
      where(course_reference_timelines: { default: true }).
      merge(Course::ReferenceTime.order(:start_at))
  end)

  scope :ordered_by_date_and_title, (lambda do
    includes(reference_times: :reference_timeline).
      where(course_reference_timelines: { default: true }).
      merge(Course::ReferenceTime.order(:start_at)).
      order(:title)
  end)

  # @!method self.published
  #   Returns only the lesson plan items that are published.
  scope :published, (lambda do
    where(published: true)
  end)

  scope :eager_load_personal_times_for, (lambda do |course_user|
    # Hacky code: We can't write the full join ourselves as Rails won't know how to load the association into memory
    # Maybe an N + 1 for personal times isn't that bad
    eager_load(:personal_times).
      joins(sanitize_sql_array(['AND course_personal_times.course_user_id = ?', course_user.id]))
  end)

  scope :eager_load_reference_times_for, (lambda do |course_user|
    eager_load(:reference_times).
      where(course_reference_times: { reference_timeline_id: course_user.reference_timeline_id ||
            course_user.course.default_reference_timeline.id })
  end)

  # @!method self.with_actable_types
  #   Scopes the lesson plan items to those which belong to the given actable_types.
  #   Each actable type is further scoped to return the IDs of items for display.
  #   actable_data is provided to help the actable types figure out what should be displayed.
  #
  # @param actable_hash [Hash{String => Array<String> or nil}] Hash of actable_names to data.
  scope :with_actable_types, lambda { |actable_hash|
    where(
      actable_hash.map do |actable_type, actable_data|
        "course_lesson_plan_items.id IN (#{actable_type.constantize.
        ids_showable_in_lesson_plan(actable_data).to_sql})"
      end.join(' OR ')
    )
  }

  # @!method self.opening_within_next_day
  #   Scopes the lesson plan items to those which are opening in the next 24 hours.
  scope :opening_within_next_day, (lambda do
    includes(reference_times: :reference_timeline).
        where(course_reference_timelines: { default: true }).
        merge(Course::ReferenceTime.where(start_at: (Time.zone.now)..(1.day.from_now))).
        references(reference_times: :reference_timeline)
  end)

  belongs_to :course, inverse_of: :lesson_plan_items
  has_many :todos, class_name: Course::LessonPlan::Todo.name, inverse_of: :item, dependent: :destroy

  # TODO(#3092): Figure out what to do with monkey-patched start_at / bonus_start_at / end_at
  delegate :start_at, :start_at=, :start_at_changed?, :bonus_end_at, :bonus_end_at=, :bonus_end_at_changed?,
           :end_at, :end_at=, :end_at_changed?,
           to: :default_reference_time
  before_validation :link_default_reference_time

  # Returns a frozen CourseReferenceTime or CoursePersonalTime.
  # The calling function is responsible for eager-loading both associations if calling time_for on a lot of items.
  # TODO(#3902): Lookup user's reference timeline before defaulting to default reference timeline
  def time_for(course_user)
    personal_time = eager_loaded_personal_time_for(course_user)
    reference_time = eager_loaded_reference_time_for(course_user)
    (personal_time || reference_time).dup.freeze
  end

  def eager_loaded_personal_time_for(course_user)
    # Do not make a separate call to DB if personal_times has already been preloaded
    if personal_times.loaded?
      personal_times.find { |x| x.course_user_id == course_user.id }
    else
      personal_times.find_by(course_personal_times: { course_user_id: course_user.id })
    end
  end

  def eager_loaded_reference_time_for(course_user)
    # Do not make a separate call to DB if reference_times has already been preloaded
    reference_timeline_id = course_user.reference_timeline_id || course_user.course.default_reference_timeline.id
    if reference_times.loaded?
      reference_times.find { |x| x.reference_timeline_id == reference_timeline_id }
    else
      reference_times.find_by(course_reference_times: { reference_timeline_id: reference_timeline_id })
    end
  end

  # Gets the existing personal time for course_user, or instantiates and returns a new one
  def setdefault_personal_time_for(course_user)
    eager_loaded_personal_time_for(course_user) || personal_times.new(course_user: course_user)
  end

  # Finds the lesson plan items which are starting within the next day for a given course.
  # Rearrange the items into a hash keyed by the actable type as a string.
  # For example:
  # {
  #   ActableType_1_as_String => [ActableItems...],
  #   ActableType_2_as_String => [ActableItems...]
  # }
  #
  # @param course [Course] The course to check for published items starting within the next day.
  # @return [Hash]
  def self.upcoming_items_from_course_by_type(course)
    opening_items = course.lesson_plan_items.published.opening_within_next_day
    opening_items_hash = Hash.new { |hash, actable_type| hash[actable_type] = [] }
    opening_items.select { |item| item.actable.include_in_consolidated_email?(:opening) }.
      each do |item|
        opening_items_hash[item.actable_type].push(item.actable)
      end
    # Sort the items for each actable type by start_at time, followed by title.
    opening_items_hash.each_value { |items| items.sort_by! { |item| [item.start_at, item.title] } }
  end

  # Copy attributes for lesson plan item from the object being duplicated.
  # Shift the time related fields.
  #
  # @param other [Object] The source object to copy attributes from.
  # @param duplicator [Duplicator] The Duplicator object
  def copy_attributes(other, duplicator)
    self.course = duplicator.options[:destination_course]
    self.default_reference_time = duplicator.duplicate(other.default_reference_time)

    # TODO(#3092):
    #   - For course duplication, we can copy all reference timelines
    #   - For object duplication, we need to figure out which reference timelines
    other_reference_times = other.reference_times - [other.default_reference_time]
    self.reference_times = duplicator.duplicate(other_reference_times).unshift(default_reference_time)

    self.title = other.title
    self.description = other.description
    self.published = duplicator.options[:unpublish_all] ? false : other.published
    self.base_exp = other.base_exp
    self.time_bonus_exp = other.time_bonus_exp
  end

  # Test if the lesson plan item has started for self directed learning.
  #
  # @return [Boolean]
  def self_directed_started?
    if course&.advance_start_at_duration
      start_at.blank? || start_at - course.advance_start_at_duration < Time.zone.now
    else
      started?
    end
  end

  private

  # Sets default EXP values
  def set_default_values
    self.base_exp ||= 0
    self.time_bonus_exp ||= 0
  end

  def set_default_reference_time
    self.default_reference_time ||= Course::ReferenceTime.new(lesson_plan_item: self)
  end

  def link_default_reference_time
    self.default_reference_time.reference_timeline = course.default_reference_timeline
    self.default_reference_time.lesson_plan_item = self
  end

  # TODO(#3092): Validate only one for each reference timeline
  def validate_only_one_default_reference_time
    num_defaults = reference_times.
                   includes(:reference_timeline).
                   where(course_reference_timelines: { default: true }).
                   count
    return if num_defaults <= 1 # Could be 0 if item is new
    errors.add(:reference_times, :must_have_at_most_one_default)
  end

  # User must set bonus_end_at if there's bonus exp
  def validate_presence_of_bonus_end_at
    return unless time_bonus_exp && time_bonus_exp > 0 && bonus_end_at.blank?
    errors.add(:bonus_end_at, :required)
  end

  def validate_start_at_cannot_be_after_end_at
    return unless end_at && start_at && start_at > end_at
    errors.add(:start_at, :cannot_be_after_end_at)
  end
end
