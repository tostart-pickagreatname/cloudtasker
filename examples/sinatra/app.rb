# frozen_string_literal: true

require 'sinatra'

# Require project files
Dir.glob('./config/initializers/*.rb').sort.each { |file| require file }
Dir.glob('./app/workers/*.rb').sort.each { |file| require file }

#---------------------------------------------------
# Routes
#---------------------------------------------------

get '/' do
  'Hello!'
end

post '/cloudtasker/run' do
  # Get authorization token from custom header (since v0.14.0) or fallback to
  # former authorization header (jobs enqueued by v0.13 and below)
  auth_token = request.env['HTTP_X_CLOUDTASKER_AUTHORIZATION'].to_s.split.last ||
               request.env['HTTP_AUTHORIZATION'].to_s.split.last
  Cloudtasker::Authenticator.verify!(auth_token)

  # Capture content and decode content
  content = request.body.read
  content = Base64.decode64(content) if request.env['HTTP_CONTENT_TRANSFER_ENCODING'].to_s.downcase == 'base64'

  # Format job payload
  payload = JSON.parse(content)
                .merge(
                  job_retries: request.env[Cloudtasker::Config::RETRY_HEADER].to_i,
                  task_id: request.env[Cloudtasker::Config::TASK_ID_HEADER]
                )

  # Process payload
  Cloudtasker::WorkerHandler.execute_from_payload!(payload)
  return 204
rescue Cloudtasker::DeadWorkerError
  # 205: job will NOT be retried
  return 205
rescue Cloudtasker::AuthenticationError
  # 401: Unauthorized
  return 401
rescue Cloudtasker::InvalidWorkerError
  # 404: Job will be retried
  return 404
rescue StandardError
  # 422: Job will be retried
  return 423
end
