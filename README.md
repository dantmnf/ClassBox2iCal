# ClassBox2iCal
Export ClassBox (课程格子) timetables to iCalendar file

### Prerequisites
```gem install icalendar```

### Usage
    $ ruby ClassBox2iCal.rb
    ClassBox username: 12450
    Password for 12450:
    logging in...
    Found 2 semesters, choose one:
      15. 2016年春季学期
      13. 2015年秋季学期
    enter semester ID to export[15]:
    save iCalendar to: 2016年春季学期.ics
    
    $ cat 2016年春季学期.ics
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:icalendar-ruby
    CALSCALE:GREGORIAN
    X-WR-CALNAME:2016年春季学期
    BEGIN:VEVENT
    ... (truncated)


### License
UNLICENSED.
