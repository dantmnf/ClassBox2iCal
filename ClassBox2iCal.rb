#!/usr/bin/env ruby
#encoding: utf-8

begin
  require 'icalendar'
rescue LoadError
  STDERR.puts 'ERROR: install icalendar gem first'
end
require 'net/http'
require 'cgi'
require 'uri'
require 'readline'
require 'io/console'
require 'json'

WEEKDAYS = %w( MO TU WE TH FR SA SU )

SALT='5a68fef494321ab6bd9bfe7c7f99c9cfcf4c85553fb8db6690d07310a8666dbffee5f23281659cbc39464ef0aa43f898a992f989827a01bea52b9e38f8cbcc40'
def sign_request(uri)
  params = CGI.parse uri.query
  devicetype = (params['devicetype'].last rescue '').to_s
  request_time = (params['request_time'].last rescue '').to_s
  token = (params['token'].last rescue '').to_s
  version = (params['version'].last rescue '').to_s
  sha1 = Digest::SHA1.new
  sha1 << SALT << devicetype << request_time << token << version
  sha1.hexdigest
end

def get_interval(a)
  return 1 if a.is_a? Range
  return nil if a.length < 2
  a = a.dup
  s = a.shift
  interval = a.first-s
  until a.length < 2
    s2 = a.shift
    return nil if a.first-s2 != interval
  end
  interval
end

def get_time(week1, relweek, weekday, timeslots, class_time)
  date = week1 + (relweek - 1) * 7 + weekday - 1
  starttime = date.to_time + class_time[timeslots.first-1].first
  endtime = date.to_time + class_time[timeslots.last-1].last
  return starttime, endtime
end

def get_rrule(weeks, weekdays)
  count = weeks.count * weekdays.length
  interval = get_interval(weeks)
  bydays = weekdays.map{|i| WEEKDAYS[i-1] }.join(',')
  "FREQ=WEEKLY;WKST=MO;COUNT=#{count};INTERVAL=#{interval};BYDAY=#{bydays}"
end

def parse_range(weeksstr)
  if weeksstr['-']
    Range.new(*weeksstr.split('-', 2).map(&:to_i)).to_a
  elsif weeksstr[',']
    weeksstr.split(',').map(&:to_i)
  else
    [weeksstr.to_i]
  end
end

def course_to_events(course, week1, class_time)
  units = course['course_units']
  units.map do |unit|
    event = Icalendar::Event.new
    event.summary = course['name']
    event.location = unit['room'] unless unit['room'].nil? || unit['room'].empty?
    weeks = parse_range unit['weeks']
    slots = parse_range unit['time_slots']
    event.dtstart, event.dtend = get_time(week1, weeks.first, unit['day_of_week'], slots, class_time)
    if weeks.length > 1
      event.rrule = get_rrule(weeks, [unit['day_of_week']])
    end
    event
  end
end

def export_semester(semester, class_time)
  cal = Icalendar::Calendar.new
  name = semester['semester']['name']
  cal.x_wr_calname = name
  week1 = Date.parse semester['semester']['begin_date']
  week1 -= 1 unless week1.monday?
  semester['courses'].each do |course|
    course_to_events(course, week1, class_time).each{|ev| cal.add_event ev }
  end
  orig_hook = Readline.pre_input_hook
  
  Readline.pre_input_hook = -> do
    Readline.insert_text "#{name}.ics"
    Readline.redisplay
    orig_hook.call if orig_hook
    Readline.pre_input_hook = orig_hook
  end
  filename = Readline.readline('save iCalendar to: ', false)
  open(filename, 'wb') {|f| f.print cal.to_ical }
end

def login_success(obj)
  active_semester_id = obj['persistence_data']['app_data']['semesters_info']['active_semester_id']
  semesters = obj['persistence_data']['app_data']['semesters_info']['semesters']
  if semesters.length > 1
    STDOUT.puts "Found #{semesters.length} semesters, choose one:"
    semesters.each do |semester|
      STDOUT.printf("  %2d. %s\n", semester['semester']['id'], semester['semester']['name'])
    end
    STDOUT.printf('enter semester ID to export[%d]: ', active_semester_id)
    if val = STDIN.gets.to_i != 0
      active_semester_id = val
    end
  end
  semester = semesters.find{|x| x['semester']['id'] == active_semester_id}
  class_time = JSON.parse obj['persistence_data']['app_data']['user_data']['class_time']
  class_time.each do |span|
    span.map! do |t|
      h, m = t.split(":", 2).map(&:to_i)
      h * 3600 + m * 60
    end
  end
  if semester
    export_semester(semester, class_time)
  else
    STDERR.puts 'ERROR: no such semester'
  end
end

def main
  STDOUT.print 'ClassBox username: '
  username = STDIN.gets.chomp

  STDOUT.print "Password for #{username}: "
  password = STDIN.noecho(&:gets).chomp
  print "\nlogging in...\n"
  uri = URI.parse('http://kechenggezi.com/mobile/login.json?version=8.1.4&device_type=android&request_time=' +
                  sprintf('%.12E', Time.now.to_f).sub(/\+0+/, ''))
  req = Net::HTTP::Post.new(uri)
  req.content_type = 'application/json; charset=utf-8'
  req.body = JSON.generate({
      "account"       => username,
      "password"      => password,
      "version"       => "8.1.4",
      "screen_width"  => 1440,
      "screen_height" => 2392
  })
  req['signature'] = sign_request(uri)
  req['User-Agent'] = 'Dalvik/2.1.0 (Linux; U; Android 6.0; Google Nexus 6P - 6.0.0 - API 23 - 1440x2560 Build/MRA58K)'

  response = Net::HTTP.start(uri.hostname, uri.port) do |client|
    client.request req
  end

  case response
  when Net::HTTPSuccess
    result = JSON.parse(response.body)
    if result['success']
      login_success(result)
    else
      STDERR.puts 'ERROR: login failed'
    end
  else
    STDERR.puts 'ERROR: bad response'
  end
end

main
