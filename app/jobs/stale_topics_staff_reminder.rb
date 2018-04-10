require 'action_view'
require 'active_support/core_ext/integer/inflections'

class StaleTopicsStaffReminder
  include Sidekiq::Worker
  include ActionView::Helpers::DateHelper

  sidekiq_options :retry => false

  def perform(topic_id)
    topic = Topic.find_by(id: topic_id)
    time_difference = distance_of_time_in_words_to_now(topic.last_posted_at, scope: 'datetime.distance_in_words_verbose')
    ordinalized_index = topic.custom_fields["staff_reminder_count"].to_i.ordinalize
    url = "/t/#{topic_id}"
    post = PostCreator.create!(
      Discourse.system_user,
      target_group_names: [SiteSetting.stale_topics_remind_staff_group.to_s],
      archetype: Archetype.private_message,
      subtype: TopicSubtype.system_message,
      title: I18n.t("stale_topics_staff_reminder.subject_template"),
      raw:   I18n.t("stale_topics_staff_reminder.text_body_template", base_url: Discourse.base_url, url: url, time_frame: time_difference, ordinalize_index: ordinalized_index)
    )


    # If the reminder flag is still true, reinstantiate another worker instance.
    # Additionally update the worker to the retry interval instead of the default
    if topic.custom_fields["staff_needs_reminder"]
      duration = SiteSetting.stale_topics_retry_remind_staff_duration
      units = SiteSetting.stale_topics_retry_remind_staff_interval_units.to_sym
      ::StaleTopic.handle_staff_reminder_job(topic, true, units, duration)
    end
  end
end