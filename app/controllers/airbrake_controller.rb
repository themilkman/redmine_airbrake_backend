require 'redmine_airbrake_backend/notice'

class AirbrakeController < ::ApplicationController
  protect_from_forgery except: :notice
  prepend_before_filter :parse_notice_and_api_auth
  before_filter :load_records

  accept_api_auth :notice

  def notice
    return unless authorize(:issues, :create)

    load_or_initialize_issue

    custom_field_values = {}

    # Error hash
    custom_field_values[notice_hash_field.id] = notice_hash if @issue.new_record?

    # Update occurrences
    if occurrences_field.present?
      occurrences_value = @issue.custom_value_for(occurrences_field.id)
      custom_field_values[occurrences_field.id] = ((occurrences_value ? occurrences_value.value.to_i : 0) + 1).to_s
    end

    @issue.custom_field_values = custom_field_values

    # Reopen if closed
    if reopen? && @issue.status.is_closed?
      desc = "*Issue reopened after occurring again in _#{@notice.env[:environment_name]}_ environment.*"
      desc << "\n\n#{render_description}" if project_setting(:reopen_repeat_description)

      @issue.status = IssueStatus.where(is_default: true).order(:position).first
      @issue.init_journal(User.current, desc)
    end

    if @issue.save
      render xml: {
        notice: {
          id: notice_hash,
          url: issue_url(@issue)
        }
      }
    else
      render nothing: true, status: :internal_server_error
    end
  end

  private

  def parse_notice_and_api_auth
    @notice = RedmineAirbrakeBackend::Notice.parse(request.body)
    params[:key] = @notice.params[:api_key]
  rescue RedmineAirbrakeBackend::Notice::NoticeInvalid, RedmineAirbrakeBackend::Notice::UnsupportedVersion
    render nothing: true, status: :bad_request
  end

  # Load or initialize issue by project, tracker and airbrake hash
  def load_or_initialize_issue
    issue_ids = CustomValue.where(customized_type: Issue.name, custom_field_id: notice_hash_field.id, value: notice_hash).pluck(:customized_id)

    @issue = Issue.where(id: issue_ids, project_id: @project.id, tracker_id: @tracker.id).first
    @issue = Issue.new(
        subject: subject,
        project: @project,
        tracker: @tracker,
        author: User.current,
        category: @category,
        priority: @priority,
        description: render_description,
        assigned_to: @assignee
      ) unless @issue
  end

  def load_records
    # Project
    unless @project = Project.where(identifier: @notice.params[:project]).first
      render text: 'Project not found!', status: :bad_request
      return
    end

    # Check configuration
    if notice_hash_field.blank?
      render text: 'Custom field for notice hash is not configured!', status: :internal_server_error
      return
    end

    # Tracker
    unless (@tracker = record_for(@project.trackers, :tracker)) && @tracker.custom_fields.where(id: notice_hash_field.id).first
      render text: 'Tracker not found!', status: :bad_request
      return
    end

    # Category
    @category = record_for(@project.issue_categories, :category)

    # Priority
    @priority = record_for(IssuePriority, :priority) || IssuePriority.default

    # Assignee
    @assignee = record_for(@project.users, :assignee, [:id, :login])
  end

  def record_for(on, param_key, fields=[:id, :name])
    fields.each do |field|
      val = on.where(field => @notice.params[param_key]).first
      return val if val.present?
    end

    project_setting(param_key)
  end

  def project_setting(key)
    return nil if @project.airbrake_settings.blank?
    @project.airbrake_settings.send(key) if @project.airbrake_settings.respond_to?(key)
  end

  def subject
    s = ''
    if @notice.error[:class].blank? || @notice.error[:message].starts_with?("#{@notice.error[:class]}:")
      s = "[#{notice_hash[0..7]}] #{@notice.error[:message]}"
    else
      s = "[#{notice_hash[0..7]}] #{@notice.error[:class]} #{@notice.error[:message]}"
    end
    s[0..254].strip
  end

  def notice_hash
    h = []
    h << @notice.error[:class]
    h << @notice.error[:message]
    h += normalized_backtrace

    Digest::MD5.hexdigest(h.compact.join("\n"))
  end

  def normalized_backtrace
    if @notice.error.present? && @notice.error[:backtrace].present?
      @notice.error[:backtrace].map do |e|
        "#{e[:file]}|#{e[:method].gsub(/_\d+_/, '')}|#{e[:number]}" rescue nil
      end.compact
    else
      []
    end
  end

  def notice_hash_field
    custom_field(:hash_field)
  end

  def occurrences_field
    custom_field(:occurrences_field)
  end

  def custom_field(key)
    @project.issue_custom_fields.where(id: setting(key)).first || CustomField.where(id: setting(key), is_for_all: true).first
  end

  def reopen?
    return false if @notice.env.blank? || @notice.env[:environment_name].blank? || project_setting(:reopen_regexp).blank?
    !!(@notice.env[:environment_name] =~ /#{project_setting(:reopen_regexp)}/i)
  end

  def setting(key)
    Setting.plugin_redmine_airbrake_backend[key]
  end

  def render_description
    if template_exists?("issue_description_#{@notice.params[:type]}", 'airbrake', true)
      render_to_string(partial: "issue_description_#{@notice.params[:type]}")
    else
      render_to_string(partial: 'issue_description')
    end
  end

end
