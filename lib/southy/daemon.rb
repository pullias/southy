class Southy::Daemon

  def initialize(travel_agent, slackbot)
    @agent = travel_agent
    @slackbot = slackbot
    @config = travel_agent.config
    @active = true
    @running = false
  end

  def start(daemonize = true)
    Process.daemon if daemonize
    write_pid

    [ 'HUP', 'INT', 'QUIT', 'TERM' ].each do |sig|
      Signal.trap(sig) do
        @config.log "Interrupted with signal: #{sig}"
        kill
      end
    end

    begin
      Thread.new { @slackbot.run }
      run
    rescue => e
      @config.log "Unexpected error", e
    ensure
      cleanup
    end
  end

  def cleanup
    delete_pid
  end

  private

  def run
    @config.log "Southy is running."
    while active? do
      @running = true
      @config.reload

      @config.unconfirmed.each do |flight|
        @agent.confirm(flight)
      end

      groups = @config.upcoming.group_by { |flight| { :conf => flight.conf, :number => flight.number } }
      groups.values.each do |flights|
        flight = flights[0]
        @agent.checkin(flights) if flight.checkin_time? || flight.late_checkin_time?
      end

      sleep 0.5
    end
  end

  def active?
    @active
  end

  def kill
    @active = false
  end

  def write_pid
    File.open @config.pid_file, 'w' do |f|
      f.write Process.pid.to_s
    end
  end

  def delete_pid
    File.delete @config.pid_file if File.exists? @config.pid_file
  end
end
