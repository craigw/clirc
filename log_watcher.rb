#! /usr/bin/env ruby

require 'rubygems'
require 'hpricot'
require 'socket'

CLIRC_DIR = ENV['HOME'] + '/.clirc'

class Commit
  def initialize(fragment)
    @fragment = fragment
  end

  def to_s
    "#{author_name} committed r#{revision_number}: #{summary}"
  end

  def summary
    message = (@fragment / "msg text()")[0].to_s
    summary = message.split(/\n/)[0]
    if summary.size > 50
      summary[0,50] + "..."
    else
      summary
    end
  end

  def revision_number
    @fragment['revision']
  end

  def author_name
    (@fragment / "author text()")[0].to_s
  end
end

class LogReporter
  def initialize(project)
    @project = project
  end

  def stop
    report "Stopping."
    @thread.terminate
    @thread = nil
  end

  def start
    report "Starting."
    @thread = Thread.new do
      loop do
        report(*new_commits)
        # Jitter to spread the load a little
        jitter = [0,1,2,3,4,5].sort_by{rand}[0]
        sleep 15 + jitter
      end
    end
  end

  def report(*messages)
    Thread.new do
      messages.each do |message|
        puts "#{Time.now.to_s} | [#{@project}] #{message.to_s}"
        socket = TCPSocket.open('irccat.local', 12345)
        socket.send("[#{@project}] #{message.to_s}\r\n", 0)
        socket.close
        sleep 0.5
      end
    end
  end

  def new_commits
    return [] if head_commit == last_commit
    command = "cd #{project_dir} && svn log --xml -r#{last_commit}:HEAD #{repository_root}"
    commit_document = Hpricot(%x[#{command}])
    commits = commit_document / "logentry"
    commits = commits.to_a.map { |commit| Commit.new(commit) }
    record_last_commit(commits[-1].revision_number)
    commits
  end

  def last_commit
    if File.exist?(commit_file)
      File.open(commit_file, 'r').read.split(/\n/)[0].to_i
    else
      head_commit
    end
  end

  def head_commit
    command = "cd #{project_dir} && svn info -rHEAD #{repository_root}"
    %x[#{command}].scan(/Revision\: (\d+)/)[0][0].to_i
  end

  def repository_root
    command = "cd #{project_dir} && svn info"
    %x[#{command}].scan(/Repository Root\: (.*)/)[0][0]
  end

  def record_last_commit(commit_id)
    File.open(commit_file, 'w+') do |f|
      f.puts commit_id.to_s
      f.flush
    end
  end

  def commit_file
    CLIRC_DIR + '/data/' + @project + '.head'
  end

  def project_dir
    CLIRC_DIR + '/projects/' + @project
  end
end

class ProjectManager
  @@reporters = {}

  def ProjectManager.run
    new.run
  end

  def run
    loop do
      projects = Dir[CLIRC_DIR + '/projects/*'].map { |dir| File.basename(dir) }
      new_watches = projects - reporter_names
      stopped_watches = reporter_names - projects
      new_watches.each do |project|
        start_reporting_on(project)
      end
      stopped_watches.each do |project|
        stop_reporting_on(project)
      end
      sleep 5
    end
  end

  private
  def reporter_names
    @@reporters.keys.sort
  end

  def start_reporting_on(project)
    if !@@reporters.key?(project.to_s)
      reporter = LogReporter.new(project)
      @@reporters[project.to_s] = reporter
      reporter.start
    end
  end

  def stop_reporting_on(project)
    if @@reporters.key?(project.to_s)
      reporter = @@reporters.delete(project.to_s)
      reporter.stop
    end
  end
end

ProjectManager.run
