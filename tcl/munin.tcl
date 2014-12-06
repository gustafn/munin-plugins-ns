#
# Interface script for aolserver/naviserver. 
#
# This script is called from the munin monitoring plugins for
# aolserver and naviserver. Place it at an accessible url path of the
# web server (e.g. under the URL /SYSTEM/munin.tcl). When the script
# is placed at a different location, please configure the the
# naviserver-munin plugins
#
#   /etc/munin/plugin-conf.d/naviserver
#
# With something like
#
# [naviserver_*]
#    env.url /SYSTEM/munin?t=
#
# Most of the queried values depend on the xotcl-request-monitor
# available from the OpenACS CVS (see http://openacs.org).
#
# Gustaf Neumann      (May 2012)
#

proc mutex_sum {field scale} {
   set lockvalues [ns_queryget lockvalues ""]
   foreach s $lockvalues {set lockvalue($s) 0}
   set total 0
   foreach l [ns_info locks] {
       lassign $l name owner id nlock nbusy totalWait
       if {![info exists $field] || [set $field] eq ""} continue
       set total [expr {$total + [set $field]}]
       foreach s $lockvalues {if {$s eq $name} {set lockvalue($name) [expr {$lockvalue($name) + [set $field]}]}}
    }
    lappend output "total.value [expr {int($total*$scale)}]"
    foreach s [array names lockvalue] {
       lappend output "[string map {: _ . _} $s].value [expr {int($lockvalue($s)*$scale)}]"
    }
    return $output
}

proc cpuinfo {utime stime ttime} {
    upvar $utime utimes $stime stimes $ttime ttimes
    set HZ 100.0 ;# for more reliable handling, we should implememnt jiffies_to_timespec or jiffies_to_secs in C
    set pid [pid]
    set threadInfo [ns_info threads]
    if {[file readable /proc/$pid/statm] && [llength [lindex $threadInfo 0]] > 7} {
	foreach t $threadInfo {
	    set fn /proc/$pid/task/[lindex $t 7]/stat
	    if {[file readable $fn]} {
		set f [open $fn]; set s [read $f]; close $f
	    } elseif {[file readable /proc/$pid/task/$pid/stat]} {
		set f [open /proc/$pid/task/$pid/stat]; set s [read $f]; close $f
	    } else {
		set s ""
	    }
	    if {$s ne ""} {
		lassign $s tid comm state ppid pgrp session tty_nr tpgid flags minflt \
		    cminflt majflt cmajflt utime stime cutime cstime priority nice \
		    numthreads itrealval starttime vsize rss rsslim startcode endcode \
		    startstack kstkesp kstkeip signal blocked sigignore sigcatch wchan \
		    nswap cnswap ext_signal processor ...
		set name [lindex $t 0]
		switch -glob -- [lindex $t 0] {
		    "-main-"    { set group main }
		    "::*"       { set group tcl:[string range $name 2 end]}
		    "-sched*"   { set group scheds  }
		    "-conn:*"   { set group conns   }
		    "-driver:*" { set group drivers }
		    "-asynclogwriter*" { set group logwriter }
		    "-writer*"  { set group writers }
		    default     { set group others  }
		}
		if {![info exists ttimes($group)]} {
		    set utimes($group) 0
		    set stimes($group) 0
		    set ttimes($group) 0
		}
		set ttimes($group) [expr {$ttimes($group) + $utime*10 + $stime*10}]
		set utimes($group) [expr {$utimes($group) + $utime*10}]
		set stimes($group) [expr {$stimes($group) + $stime*10}]
	    }
	}
    }
}
switch [ns_queryget t ""] {
    "serverstats" {
        foreach s [ns_info servers] {
          foreach p [ns_server -server $s pools] {
           foreach {att value} [ns_server -server $s -pool $p stats] {
              set key serverstats($att)
              if {![info exists $key]} {
                 set $key $value
              } else {
                 set $key [expr {[set $key] + $value}]
              }
            }
          }
        }
        set stats [array get serverstats]
        set treqs $serverstats(requests)
        if {$treqs == 0} {set treqs 1}
        set tavgAcceptTime [expr {($serverstats(accepttime) * 1.0 / $treqs)}]
        set tavgQueueTime  [expr {($serverstats(queuetime)  * 1.0 / $treqs)}]
        set tavgFilterTime [expr {($serverstats(filtertime) * 1.0 / $treqs)}]
        set tavgRunTime    [expr {($serverstats(runtime)    * 1.0 / $treqs)}]
        if {[throttle do info exists lastserverstats]} {
           array set lastserverstats [throttle do set lastserverstats]
           set reqs [expr {$serverstats(requests) - $lastserverstats(requests)}]
           if {$reqs == 0} {set reqs 1}
           set avgAcceptTime [expr {(($serverstats(accepttime) - $lastserverstats(accepttime)) * 1.0 / $reqs)}]
           set avgQueueTime  [expr {(($serverstats(queuetime)  - $lastserverstats(queuetime))  * 1.0 / $reqs)}]
           set avgFilterTime [expr {(($serverstats(filtertime) - $lastserverstats(filtertime))  * 1.0 / $reqs)}]
           set avgRunTime    [expr {(($serverstats(runtime)    - $lastserverstats(runtime))    * 1.0 / $reqs)}]
        } else {
           set avgAcceptTime $tavgAcceptTime
           set avgQueueTime  $tavgQueueTime
           set avgFilterTime $tavgQueueTime
           set avgRunTime    $tavgRunTime
        }
        set ttotalTime [expr {$tavgQueueTime + $tavgFilterTime + $tavgRunTime}]
        set totalTime  [expr {$avgQueueTime + $avgFilterTime + $avgRunTime}]
        throttle do set lastserverstats $stats
        lappend output \
            "accepttime.value [format %6.4f $avgAcceptTime]" \
            "queuetime.value  [format %6.4f $avgQueueTime]" \
            "filtertime.value [format %6.4f $avgFilterTime]" \
            "runtime.value    [format %6.4f $avgRunTime]" \
            "totaltime.value  [format %6.4f $totalTime]" \
            "avgqueuetime.value  [format %6.4f $tavgQueueTime]" \
            "avgfiltertime.value [format %6.4f $tavgFilterTime]" \
            "avgruntime.value    [format %6.4f $tavgRunTime]" \
            "avgtotaltime.value  [format %6.4f $ttotalTime]"
    }

    "count" {
       set output ""
       set vars [ns_queryget vars ""]
       array set count [throttle do array get ::count]
       foreach v $vars {
         if {[info exists count($v)]} {
            set c $count($v)
         } else {
           set c 0
         }
         lappend output "[string map {: _ . _} $v].value $c"
       }
    }

    "lsof" {
        array set count {file 0 pipe 0 socket 0 tcp 0 other 0 total 0}
        foreach l [split [exec /usr/sbin/lsof -n -P +p [pid]] \n] {
            switch -glob [lindex $l 8] {
		/* {incr count(file)}
		pipe {incr count(pipe)}
		socket {incr count(socket)}
		default {if {[lindex $l 7] eq "TCP"} {incr count(tcp)} else {incr count(other)}}
            }
            incr count(total)
        }
        lappend output \
            "file.value   $count(file)" \
            "pipe.value   $count(pipe)" \
            "socket.value $count(socket)" \
            "tcp.value    $count(tcp)" \
            "other.value  $count(other)" \
            "total.value  $count(total)" 
    }

    "responsetime" {
	proc avg_last_n {list n var} {
	  upvar $var cnt
  	  set total 0.0
  	  set list [lrange $list end-[incr n -1] end]
  	  foreach d $list { set total [expr {$total+$d}] }
  	  set cnt [llength $list]
  	  return [expr {$cnt > 0 ? $total*1.0/$cnt : 0}]
	}
        set tm [throttle trend response_time_minutes]
        lappend output \
                "response_time.value [expr {[lindex $tm end]/1000.0}]" \
                "response_time_five.value [expr {[avg_last_n $tm 5 cnt]/1000.0}]"
    }

    "memsize" {
        set sizes [exec -ignorestderr /bin/ps -o vsize,rss [pid]]
        lappend output \
	    "vsize.value [expr {[lindex $sizes end-1]*1024}]" \
	    "rss.value [expr {[lindex $sizes end]*1024}]"
       
    }
    "locks.nr"   { set output [mutex_sum nlock 1] }
    "locks.busy" { set output [mutex_sum nbusy 1] }
    "locks.wait" { set output [mutex_sum totalWait 1000] }

    "logstats" {
	set output ""
	set logvalues [ns_queryget logvalues ""]
	foreach s $logvalues {set dolog($s) 1}
	foreach {key value} [ns_logctl stats] {
	    if {![info exists dolog($key)]} continue
	    lappend output "$key.value $value"
	}
    }
    
    "threads" {
        #min 1 max 30 current 6 idle 5 stopping 0
        array set thread_info [throttle do throttle server_threads]
        #set rspools [expr {[info command ::bgdelivery] ne "" ? [bgdelivery nr_running] : 0}]
        lappend output \
	    "max.value $thread_info(max)" \
            "current.value $thread_info(current)" \
            "busy.value [expr {$thread_info(current) - $thread_info(idle) - 1}]" \
            "nrthreads.value [lindex [exec -ignorestderr /bin/ps -o nlwp [pid]] 1]" 
        #"rspools.value $rspools"
    }
    "threadcpu" {
        if {[info command ::xo::system_stats] ne ""} {
	   ::xo::system_stats aggcpuinfo ut st tt
        } else {
           # TODO: cpuinfo is obsolete and should be removed in the future
           cpuinfo ut st tt
        }
	foreach group [array names tt] {
	    lappend output "time:$group.value $tt($group)"
	}
    }
    "reqmonthreads" {
          lappend output \
             "busy.value [throttle do set ::threads_busy]" \
             "current.value [throttle do set ::threads_current]"
    }
    "requests" {
        lappend  output "requests.value [throttle do set ::threads_datapoints]"
    }
    "users" {
        lassign [throttle users nr_users_time_window] activeIP10 authUsers10
        lappend  output \
           "active.value [expr {$authUsers10 + $activeIP10}]" \
           "authenticated.value $authUsers10"
    }
    "users24" {
        lassign [throttle users nr_users_per_day] activeIP24 authUsers24 
        lappend  output \
           "active.value [expr {$authUsers24 + $activeIP24}]" \
           "authenticated.value $authUsers24"
    }
    "views" {
        set tm [throttle trend minutes]
        set ts [throttle trend seconds]
        set spools [expr {[info command ::bgdelivery] ne "" ? [bgdelivery do set ::delivery_count] : 0}]
        if {$tm ne ""} {
           set views_per_sec [expr {[lindex $tm end]/60.0}]
           lappend output \
              "views_seconds.value [lindex $ts end]" \
              "views_minutes.value $views_per_sec" \
              "requests.value [ns_server connections]" \
              "alt_views.value [throttle do set ::threads_datapoints]" \
              "spools.value $spools"
        }
    }
    default {
       lappend  output "unknown.value 0"
    }

}

ns_return 200 "text/plain" [join $output \r ]

