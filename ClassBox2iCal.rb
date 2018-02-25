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

SALT = IO.read('salt').strip
def sign_request(uri)
  params = CGI.parse uri.query
  request_time = (params['request_time'].last rescue '').to_s
  digest1 = Digest::SHA1.new
  digest1 << SALT << request_time
  digest2 = Digest::SHA1.new << digest1.hexdigest[3,10]
  digest2.hexdigest
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
    #event.status = 'CONFIRMED'
    weeks = parse_range unit['weeks']
    slots = parse_range unit['time_slots']
    event.dtstart, event.dtend = get_time(week1, weeks.first, unit['day_of_week'], slots, class_time)
    if weeks.length > 1
      event.rrule = get_rrule(weeks, [unit['day_of_week']])
    end
    event.alarm do |a|
      a.action  = 'DISPLAY'
      a.trigger = '-PT30M'
    end
    event
  end
end

def export_all(semester, courses, class_time)
  cal = Icalendar::Calendar.new
  name = semester['semester']['name']
  cal.x_wr_calname = name
  week1 = Date.parse semester['semester']['begin_date']
  week1 -= 1 until week1.monday?
  courses.each do |course|
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


def presync(login)
  token = login['user_info']['token']
  uid = login['user_info']['guid']
  uri = URI.parse("https://classbox2.kechenggezi.com/api/v1/users/#{uid}/sync_all?device[agent]=Mozilla/5.0%20(Linux;%20Android%204.4.4;%20MuMu%20Build/V417IR)%20AppleWebKit/537.36%20(KHTML,%20like%20Gecko)%20Version/4.0%20Chrome/33.0.0.0%20Safari/537.36%20classbox2/10.0.2&device[app_version]=10.0.2&device[brand]=Android&device[channel]=Web&device[network]=wifi&device[platform]=android&device[unit_type]=MuMu&request_time="+Time.now.to_i.to_s)
  req = Net::HTTP::Get.new(uri)
  req['SIGNATURE'] = sign_request(uri)
  req['User-Agent'] = 'okhttp/3.8.0'
  req['Authorization'] = "Token token=#{token}"
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |client|
    client.request req
  end
  case response
  when Net::HTTPSuccess
    File.write('sync_all.json', response.body)
    result = JSON.parse(response.body)
    if result['success']
      choose_semester(login, result)
    else
      STDERR.puts 'ERROR: login failed'
    end
  else
    STDERR.puts 'ERROR: bad response'
  end
end


def choose_semester(login, sync_all)
  
  semesters = sync_all['semester_info']
  active_semester_id = semesters.map{|x| x['is_active']}.index(true) + 1
  if semesters.length > 1
    STDOUT.puts "Found #{semesters.length} semesters, choose one:"
    i = 1
    semesters.each do |semester|
      STDOUT.printf("  %2d. %s%s\n", i, semester['name'], semester['is_active'] ? ' *' : '')
    end
    loop do
      STDOUT.printf('enter semester index to export[%d]: ', active_semester_id)
      input = STDIN.gets.strip
      break if input.empty?
      num = input.to_i
      break if num == active_semester_id
      if num >= 1 && num <= semesters.length
        sync_all = switch_semester(login, semesters[num-1]['semester_id'])
        break
      end
    end
    export(login, sync_all)
  end
end

def export(login, sync_all)
  class_time = sync_all['calendar_data']['slot_times']
  class_time.each do |span|
    span.map! do |t|
      h, m = t.split(":", 2).map(&:to_i)
      h * 3600 + m * 60
    end
  end
  cal = Icalendar::Calendar.new
  name = sync_all['calendar_data']['semester']['name']
  cal.x_wr_calname = name
  week1 = Time.at(sync_all['calendar_data']['semester']['start_at']).to_date
  week1 -= 1 until week1.monday?
  sync_all['calendar_data']['courses'].each do |course|
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

def main
  STDOUT.print 'ClassBox username: '
  username = STDIN.gets.chomp

  STDOUT.print "Password for #{username}: "
  password = STDIN.noecho(&:gets).chomp
  print "\nlogging in...\n"
  uri = URI.parse('https://classbox2.kechenggezi.com/api/v1/login?request_time=' +
                  Time.now.to_i.to_s)
  req = Net::HTTP::Post.new(uri)
  req.content_type = 'application/json; charset=utf-8'
  req.body = JSON.generate({
    'device' => {
      "agent" => "Mozilla/5.0 (Linux; Android 4.4.4; MuMu Build/V417IR) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/33.0.0.0 Safari/537.36 classbox2/10.0.2",
      "app_version" => "10.0.2",
      "brand" => "Android",
      "channel" => "Web",
      "network" => "wifi",
      "platform" => "android",
      "unit_type" => "MuMu",
    },
    'user' => {
      "mobile_number" => username,
      "password" => password,
    }

  })
  req['SIGNATURE'] = sign_request(uri)
  req['User-Agent'] = 'okhttp/3.8.0'

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |client|
    client.request req
  end
  p response
  case response
  when Net::HTTPSuccess
    File.write('login.json', response.body)
    result = JSON.parse(response.body)
    if result['success']
      presync(result)
    else
      STDERR.puts 'ERROR: login failed'
    end
  else
    STDERR.puts 'ERROR: bad response'
  end
end

main
