require 'htmlentities'

module AirbrakeHelper
  # Wiki markup for a table
  def format_table(data)
    lines = []
    data.each do |key, value|
      next unless value.is_a?(String)
      lines << "|@#{key}@|#{value.strip.blank? ? value : "@#{value}@"}|"
    end
    lines.join("\n")
  end

  # Wiki markup for logs
  def format_log(data)
    lines = []
    data.each do |log|
      next unless log.is_a?(Hash)
      lines << "[#{log[:time].strftime('%F %T')}] #{log[:line]}"
    end
    lines.join("\n")
  end

  # Wiki markup for a list item
  def format_list_item(name, value)
    return '' if value.blank?

    "* *#{name}:* #{value}"
  end

  # Wiki markup for backtrace element with link to repository if possible
  def format_backtrace_element(element)
    @htmlentities ||= HTMLEntities.new

    repository = repository_for_backtrace_element(element)

    if repository.blank?
      if element[:number].blank?
        markup = "@#{@htmlentities.decode(element[:file])}@"
      else
        markup = "@#{@htmlentities.decode(element[:file])}:#{element[:number]}@"
      end
    else
      filename = @htmlentities.decode(filename_for_backtrace_element(element))

      if repository.identifier.blank?
        markup = "source:\"#{filename}#L#{element[:number]}\""
      else
        markup = "source:\"#{repository.identifier}|#{filename}#L#{element[:number]}\""
      end
    end

    markup + " in ??<notextile>#{@htmlentities.decode(element[:method])}</notextile>??"
  end

  private

  def repository_for_backtrace_element(element)
    return nil unless element[:file].start_with?('[PROJECT_ROOT]')

    filename = filename_for_backtrace_element(element)

    repositories_for_backtrace.find { |r| r.entry(filename) }
  end

  def repositories_for_backtrace
    return @_bactrace_repositories unless @_bactrace_repositories.nil?

    if @request.repository.present?
      @_bactrace_repositories = [@request.repository]
    else
      @_bactrace_repositories = @request.project.repositories.to_a
    end

    @_bactrace_repositories
  end

  def filename_for_backtrace_element(element)
    return nil if  element[:file].blank?

    element[:file][14..-1]
  end
end
