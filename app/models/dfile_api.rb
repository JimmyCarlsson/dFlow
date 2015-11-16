require 'httparty'
require 'redis'

class DfileApi

  def self.api_key
    APP_CONFIG['dfile_api_key']
  end

  def self.host
    APP_CONFIG['dfile_base_url']
  end

  def self.logger=(logger)
    @@logger ||= nil
    @@logger = logger
  end

  def self.logger
    @@logger ||= Logger.new("#{Rails.root}/log/dfile_api.log")
  end

  # Returns true of connection is successful
  def self.check_connection
    return
    check = HTTParty.get("#{host}/api/check_connection?api_key=#{api_key}")
    if check.nil? || check["status"]["code"] < 0
      logger.fatal "Script was unable to establish connection with dFile at #{host}"
    end
  end

  # TODO: Needs error handling
  def self.download_file(source, filename)
    response = HTTParty.get("#{host}/download_file", query: {
      source_file: "#{source}:#{filename}",
      api_key: api_key
    })

    return response.body
  end

  # TODO: Needs error handling
  # Returns array of {:name, :size}
  # :name == basename
  def self.list_files(source, directory, extension)
    response = HTTParty.get("#{host}/list_files", query: {
      source_dir: "#{source}:#{directory}",
      ext: extension,
        api_key: api_key
    })

    return response
  end

  # TODO: Needs error handling
  def self.move_file(from_source:, from_file:, to_source:, to_file:)
    response = HTTParty.get("#{host}/move_file", query: {
      source_file: "#{from_source}:#{from_file}",
      dest_file: "#{to_source}:#{to_file}",
      api_key: api_key
    })

    return response.body
  end

  # TODO: Needs error handling
  def self.move_folder(from_source:, from_dir:, to_source:, to_dir:)
    response = HTTParty.get("#{host}/move_folder", query: {
      source_dir: "#{from_source}:#{from_dir}",
      dest_dir: "#{to_source}:#{to_dir}",
      api_key: api_key
    })

    return response.success?
  end

  # TODO: Needs error handling
  # returns {:checksum, :msg}
  def self.checksum(source, filename)
    logger.info "#########  Starting checksum request for: #{source}:#{filename} #########"
    response = HTTParty.get("#{host}/checksum", query: {
      source_file: "#{source}:#{filename}",
      api_key: api_key
    })

    logger.info "Response from dFile: #{response.inspect}"
    if !response.success?
      raise StandardError, "Could not start a process through dFile: #{response['error']}"
    end

    process_id = response['id']

    logger.info "Process id: #{process_id}"
    if !process_id || process_id == ''
      raise StandardError, "Did not get a valid Process ID: #{process_id}"
    end

    process_result = get_process_result(process_id)
    logger.info "Process result: #{process_result}"

    return process_result
  end

  # Creates a file with given content
  def self.create_file(source:, filename:, content:, permission: nil)
    body = { dest_file: "#{source}:#{filename}",
             content: content,
               api_key: api_key
    }
    if !permission.nil?
      body['force_permission'] = permission
    end

    response = HTTParty.post("#{host}/create_file", body: body)

    return response.success?
  end

  # Copies a file
  def self.copy_file(from_source:, from_file:, to_source:, to_file:)
    response = HTTParty.get("#{host}/copy_file", query: {
      source_file: "#{from_source}:#{from_file}",
      dest_file: "#{to_source}:#{to_file}",
      api_key: api_key
    })

    return response.success?
  end

  private
  # Returns result from redis db
  def self.get_process_result(process_id)

    # Load Redis config
    redis = Redis.new(db: APP_CONFIG['redis_db']['db'], host: APP_CONFIG['redis_db']['host'])

    logger.info "Redis settings: #{redis.inspect}"
    while !redis.get("dFile:processes:#{process_id}:state:done") do
      sleep 0.1
    end

    value = redis.get("dFile:processes:#{process_id}:value")

    logger.info "Value from Redis for #{process_id}: #{value}"
    if !value
      raise StandardError, redis.get("dFile:processes:#{process_id}:error")
    end

    return value
  end
end