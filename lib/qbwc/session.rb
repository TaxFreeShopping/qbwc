class QBWC::Session
  include Enumerable

  attr_reader :current_job, :current_request, :saved_requests, :progress
  attr_reader :qbwc_iterator_queue, :qbwc_iterating

  @@session = nil

  def initialize
    @current_job = nil
    @current_request = nil
    @saved_requests = []

    @qbwc_iterator_queue = []
    @qbwc_iterating = false

    @@session = self
    reset
  end

  def reset
    @progress = QBWC.jobs.blank? ? 100 : 0
    @requests = build_request_generator(enabled_jobs)
  end

  def finished?
    @progress == 100
  end

  def next
    @requests.alive? ? @requests.resume : nil
  end

  def process_saved_responses
    @saved_requests.each { |r| r.process_response }
  end

  def end_session!
    @progress = 100
  end

  private

  def enabled_jobs
    QBWC.jobs.values.select { |j| j.enabled? }
  end

  def build_request_generator(jobs)
    Fiber.new do
      @current_job = next_job(jobs)
      while(@current_job)
        @current_request = @current_job.try(:request)
        Fiber.yield @current_request
        @current_job = next_job(jobs)
      end
      nil
    end
  end

  def next_job(jobs)
    job_names = jobs.map &:name
    if current_job_name.blank?
      set_current_job_name job_names.first
      job_index = 0
    else
      job_index = job_names.find_index(current_job_name) + 1
    end

    up_next = jobs[job_index]
    set_current_job_name(up_next.try :name)

    up_next
  end

  def current_job_name
    if QBWC.redis
      QBWC.redis.get('quickbooks_current_job_name')
    else
      @current_job_name
    end
  end

  def set_current_job_name(value)
    if QBWC.redis
      puts "FINISHED: #{current_job}"
      QBWC.redis.set('quickbooks_current_job_name', value)
      puts "STARTED: #{current_job}"
    else
      @current_job_name = value
    end
  end

  def parse_response_header(response)
    return unless response['xml_attributes']

    status_code, status_severity, status_message, iterator_remaining_count, iterator_id = \
      response['xml_attributes'].values_at('statusCode', 'statusSeverity', 'statusMessage', 
                                               'iteratorRemainingCount', 'iteratorID') 

    if status_severity == 'Error' || status_code.to_i > 1 || response.keys.size <= 1
      @current_request.error = "QBWC ERROR: #{status_code} - #{status_message}"
    else
      if iterator_remaining_count.to_i > 0
        @qbwc_iterating = true
        new_request = @current_request.to_hash
        new_request.delete('xml_attributes')
        new_request.values.first['xml_attributes'] = {'iterator' => 'Continue', 'iteratorID' => iterator_id}
        @qbwc_iterator_queue << QBWC::Request.new(new_request, @current_request.response_proc)
      else
        @qbwc_iterating = false
      end
    end
  end

  class << self
    def handle_response(qbxml_response)
      response = QBWC.parser.from_qbxml(qbxml_response)
      key = nil

      if response['qbxml']['qbxml_msgs_rs'].present?
        keys = response['qbxml']['qbxml_msgs_rs'].keys
        keys = keys - ['xml_attributes']
        key = keys.first
        key = key[0...-3] if key
      end

      if key
        processor = QBWC.processors[key]
        processor && processor.call(response)
      end
    end

    def new_or_unfinished
      (!@@session || @@session.finished?) ? new : @@session
    end

    def session
      @@session
    end
  end
end
