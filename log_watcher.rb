#! /usr/bin/env ruby

require 'rubygems'
require 'hpricot'
require 'socket'

CLIRC_DIR = ENV['HOME'] + '/.clirc'

module Subversion
  def Subversion.client_binary
    "/opt/local/bin/svn"
  end
end

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
      summary[0,46] + "..."
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

  def report
    announce(*new_commits)
  end

  def announce(*messages)
    socket = TCPSocket.open('irccat.local', 12345)
    messages.each do |message|
      puts "#{Time.now.to_s} | [#{@project}] #{message.to_s}"
      socket.send("[#{@project}] #{message.to_s}\r\n", 0)
      sleep 0.5
    end  
    socket.close
  end

  def new_commits
    puts "[#{@project}] Getting commits since #{last_commit}" if $DEBUG
    if head_commit != last_commit
      command = "cd #{project_dir} && #{Subversion.client_binary} log --xml -r#{last_commit.to_i + 1}:HEAD #{repository_root}"
      commit_document = Hpricot(%x[#{command}])
      commits = commit_document / "logentry"
      commits = commits.to_a.map { |commit| Commit.new(commit) }
      puts "[#{@project}] #{commits.size} commits: #{commits.map { |c| c.revision_number }.join(', ')}."
      record_last_commit(commits[-1].revision_number)
      commits
    else
      record_last_commit(head_commit) if !File.exist?(commit_file)
      []
    end
  end

  def last_commit
    if File.exist?(commit_file)
      File.open(commit_file, 'r').read.split(/\n/)[0].to_i
    else
      head_commit
    end
  end

  def head_commit
    command = "cd #{project_dir} && #{Subversion.client_binary} info -rHEAD #{repository_root}"
    %x[#{command}].scan(/Revision\: (\d+)/)[0][0].to_i
  end

  def repository_root
    command = "cd #{project_dir} && #{Subversion.client_binary} info"
    %x[#{command}].scan(/Repository Root\: (.*)/)[0][0]
  end

  def record_last_commit(commit_id)
    puts "Recording last commit as #{commit_id}" if $DEBUG
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
  def ProjectManager.run
    new.run
  end

  def run
    projects = Dir[CLIRC_DIR + '/projects/*'].map { |dir| File.basename(dir) }
    projects.each do |project|
      reporting_on(project)
    end
  end

  private

  def reporting_on(project)
    reporter = LogReporter.new(project)
    reporter.report
  end
end

ProjectManager.run