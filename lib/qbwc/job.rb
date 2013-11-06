class QBWC::Job

  attr_reader :name, :response_proc, :requests, :error_proc

  def initialize(name, &block)
    @name = name
    @enabled = true
    @requests = block
  end

  def set_response_proc(&block) 
    @response_proc = block
  end

  def set_error_proc(&block)
    @error_proc = block
  end

  def enable
    @enabled = true
  end

  def disable
    @enabled = false
  end

  def handle_error
    if @error_proc
      @error_proc.call
    end
  end

  def enabled?
    @enabled
  end

  def request
    QBWC::Request.new(@requests.call, @response_proc )
  end
end
