# Controller for airbrake notices
class AirbrakeReportController < ::AirbrakeController
  prepend_before_filter :parse_json_request

  accept_api_auth :report

  # Handle airbrake reports
  def report
    # TODO
    render json: {
      notice: {
        id: (@results.first[:hash] rescue nil)
      }
    }
  end
end
