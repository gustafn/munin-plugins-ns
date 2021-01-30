#
# Interface script for NaviServer (and partly as well ofr AOLserver).
#
# This script is called from the munin monitoring plugins for
# NaviServer. Place it at an accessible url path of the web server
# (e.g. under the URL /SYSTEM/munin.tcl). When the script is placed at
# a different location, please configure the naviserver-munin plugins
#
#   /etc/munin/plugin-conf.d/naviserver
#
# With something like
#
# [naviserver_*]
#    env.url /SYSTEM/munin?t=
#
# Some of the queried values depend on the xotcl-request-monitor
# available from the OpenACS CVS (see https://openacs.org/).
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
    foreach s $lockvalues {
      if {$s eq $name} {
        set lockvalue($name) [expr {$lockvalue($name) + [set $field]}]
      }
    }
  }
  lappend output "total.value [expr {int($total*$scale)}]"
  foreach s [array names lockvalue] {
    lappend output "[string map {: _ . _} $s].value [expr {int($lockvalue($s)*$scale)}]"
  }
  return $output
}

proc classify_threadname {name} {
  switch -glob -- $name {
    "-asynclogwriter*" { set group logwriter }
    "-conn:*"   { set group conn    }
    "-driver*"  { set group driver  }
    "-ns_job*"  { set group job     }
    "-main-"    { set group main    }
    "-nsproxy*" { set group nsproxy }
    "-sched*"   { set group sched   }
    "-socks*"   { set group socks   }
    "-spooler*" { set group spooler }
    "-writer*"  { set group writer  }
    "-nsjob*"   { set group nsjob   }
    "::*"       { set group tcl:[string range $name 2 end]}
    default     { set group others  }
  }
  return $group
}

proc cpuinfo {utime stime ttime} {
  upvar $utime utimes $stime stimes $ttime ttimes
  set HZ 100.0 ;# for more reliable handling, we should implement jiffies_to_timespec or jiffies_to_secs in C
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
        set group [classify_threadname [lindex $t 0]]
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
    array set serverstats {tracetime 0}
    set servers [ns_info servers]
    if {[llength $servers] == 0} {set servers [ns_info server]}
    foreach s $servers {
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
    set tavgTraceTime  [expr {($serverstats(tracetime)  * 1.0 / $treqs)}]
    if {[throttle do info exists lastserverstats]} {
      array set lastserverstats [throttle do set lastserverstats]
      set reqs [expr {$serverstats(requests) - $lastserverstats(requests)}]
      if {$reqs == 0} {set reqs 1}
      set avgAcceptTime [expr {(($serverstats(accepttime) - $lastserverstats(accepttime)) * 1.0 / $reqs)}]
      set avgQueueTime  [expr {(($serverstats(queuetime)  - $lastserverstats(queuetime))  * 1.0 / $reqs)}]
      set avgFilterTime [expr {(($serverstats(filtertime) - $lastserverstats(filtertime)) * 1.0 / $reqs)}]
      set avgRunTime    [expr {(($serverstats(runtime)    - $lastserverstats(runtime))    * 1.0 / $reqs)}]
      set avgTraceTime  [expr {(($serverstats(tracetime)  - $lastserverstats(tracetime))  * 1.0 / $reqs)}]
    } else {
      set avgAcceptTime $tavgAcceptTime
      set avgQueueTime  $tavgQueueTime
      set avgFilterTime $tavgQueueTime
      set avgRunTime    $tavgRunTime
      set avgTraceTime  $tavgTraceTime
    }
    set ttotalTime [expr {$tavgQueueTime + $tavgFilterTime + $tavgRunTime + $tavgTraceTime}]
    set totalTime  [expr {$avgQueueTime  + $avgFilterTime  + $avgRunTime  + $avgTraceTime }]
    throttle do set lastserverstats $stats
    lappend output \
        "accepttime.value [format %6.4f $avgAcceptTime]" \
        "queuetime.value  [format %6.4f $avgQueueTime]" \
        "filtertime.value [format %6.4f $avgFilterTime]" \
        "runtime.value    [format %6.4f $avgRunTime]" \
        "tracetime.value  [format %6.4f $avgTraceTime]" \
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
    set types {CHR DIR DEL FIFO IPv4 IPv6 PIPE REG so STSO sock unix other}
    foreach t $types {set count($t) 0}
    foreach lsof {/usr/sbin/lsof /usr/bin/lsof} {
      if {[file exists $lsof]} break
    }
    foreach l [split [exec $lsof -n -P +p [pid] 2>/dev/null] \n] {
      #
      # Just look for entries with file descriptors.
      #
      if {![string match {[1234567890]*} [lindex $l 3]]} continue

      set t [lindex $l 4]
      if {$t eq "REG" && [string match "*.so*" [lindex $l end]]} {
        set t so
      }
      if {$t in $types} {
        incr count($t)
      } else {
        incr count(other)
      }
      incr count(total)
    }
    foreach t $types {
      lappend output "$t.value $count($t)"
    }
    lappend output "total.value  $count(total)"
  }

  "responsetime" {
    set urls [ns_queryget urls ""]
    proc avg_last_n {list n var} {
      upvar $var cnt
      set total 0.0
      set list [lrange $list end-[incr n -1] end]
      foreach d $list { set total [expr {$total+$d}] }
      set cnt [llength $list]
      return [expr {$cnt > 0 ? $total*1.0/$cnt : 0}]
    }
    set tm [throttle trend response_time_minutes]
    set extra {}
    foreach url $urls {
      if {[throttle do info exists ::count(calls:$url)]} {
        set agg_time [throttle do set ::agg_time($url)]
        set count    [throttle do set ::count(calls:$url)]
        throttle do unset ::agg_time($url)
        throttle do unset ::count(calls:$url)
        set ds $url
        regsub -all {[^A-Za-z0-9_]} $ds _ ds
        lappend extra  "u_$ds.value [expr {$agg_time/($count*1000.0)}]"
      }
    }
    lappend output \
        "response_time.value [expr {[lindex $tm end]/1000.0}]" \
        "response_time_five.value [expr {[avg_last_n $tm 5 cnt]/1000.0}]" \
        {*}$extra
  }

  "bandwidth" {
    set total 0
    foreach s [ns_info servers] {
      set server [string map {: _ . _} $s]
      set server_total($server) 0
      foreach p [ns_server -server $s pools] {
        set d [ns_server -server $s -pool $p stats]
        if {![dict exists $d sent]} continue
        if {$p eq ""} {set p default}
        set sent [dict get $d sent]
        incr server_total($server) $sent
        incr total $sent
        lappend output \
            "sent_${server}_${p}.value $sent"
      }
      lappend output \
          "sent_${server}.value $server_total($server)"
    }
    lappend output \
        "sent_total.value $total"
  }

  "memsize" {
    set uss 0
    if {[file readable /proc/[pid]/statm]} {
      #
      # result in pages, typically 4K
      #
      set F [open /proc/[pid]/statm]; set c [read $F]; close $F
      lassign $c vsize rss shared
      set uss   [format %.2f [expr {($rss-$shared) * 4}]]
      set rss   [format %.2f [expr {$rss           * 4}]]
      set vsize [format %.2f [expr {$vsize         * 4}]]
    }
    if {![info exists rss]} {
      set sizes [exec -ignorestderr /bin/ps -o vsize,rss [pid]]
      set vsize [lindex $sizes end-1]
      set rss   [lindex $sizes end]
    }
    set smemPath ""
    foreach path {/usr/bin/smem /bin/smem} {
      if {[file exists $path]} {
        set smemPath $path
        break
      }
    }
    set swap 0
    set pss 0
    #
    # Ignore errors, e.g. when "exec" cannot be performed due to
    # "can't fork" etc.
    #
    catch {
      if {$smemPath ne ""} {
        set smem [exec -ignorestderr $smemPath -t | fgrep [pid]]
        foreach l [split $smem \n] {
          regexp {^\s*(\d+)\s.*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$} $l . pid swap uss pss rss
          if {$pid eq [pid]} {
            break
          }
        }
      }
    }
    lappend output \
        "vsize.value [expr {$vsize * 1024}]" \
        "rss.value   [expr {$rss * 1024}]" \
        "uss.value   [expr {$uss * 1024}]" \
        "pss.value   [expr {$pss * 1024}]" \
        "swap.value  [expr {$swap * 1024}]"
  }


  "locks.nr"   { set output [mutex_sum nlock 1] }
  "locks.busy" { set output [mutex_sum nbusy 1] }
  "locks.wait" { set output [mutex_sum totalWait 1000] }

  "logstats" {
    set output ""
    set logvalues [ns_queryget logvalues ""]
    foreach s $logvalues {set dolog($s) 1}
    if {[catch {set pairs [ns_logctl stats]}]} {
      foreach key [array names dolog] {
        lappend output "$key.value 0"
      }
    } else {
      foreach {key value} $pairs {
        if {![info exists dolog($key)]} continue
        lappend output "$key.value $value"
      }
    }
  }

  "dbstats" {
    set output ""
    set vars [ns_queryget vars ""]
    set pool [ns_queryget pool ""]
    foreach s $vars {set dolog($s) 1}
    if {[catch {set pairs [ns_db stats]}]} {
      foreach key [array names dolog] {
        lappend output "$key.value 0"
      }
    } else {
      foreach {p values} $pairs {
        if {$p ne $pool} continue
        foreach {key value} $values {
          if {![info exists dolog($key)]} continue
          if {![string is integer -strict $value]} {
            # assume floating point number in secs, compute ms
            set value [expr {round ($value*1000)}]
          }
          lappend output "$key.value $value"
        }
      }
    }
  }

  "dbstats2" {
    set output ""
    set vars [ns_queryget vars ""]
    foreach s $vars {set dolog($s) 1}
    if {[catch {set pairs [ns_db stats]}]} {
      foreach key [array names dolog] {
        lappend output "$key.value 0"
      }
    } else {
      foreach {pool values} $pairs {
        foreach {key value} $values {
          if {![info exists dolog($key)]} continue
          if {![string is integer -strict $value]} {
            # assume floating point number in secs, compute ms
            set value [expr {round ($value*1000)}]
          }
          lappend output "${pool}_$key.value $value"
        }
      }
    }
  }

  "threads" {
    set max_total 0
    set current_total 0
    set busy_total 0
    foreach s [ns_info servers] {
      foreach p [ns_server -server $s pools] {
        set d [ns_server -server $s -pool $p threads]
        # returns e.g.: min 1 max 30 current 6 idle 5 stopping 0
        set max [dict get $d max]
        set current [dict get $d current]
        set busy [expr {([dict get $d current] - [dict get $d idle])}]
        if {$p eq "monitor"} {
          # Don't count the actual monitoring thread collecting the
          # statistics. Otherwise, we would have the impression, there is always at least one thread busy
          incr busy -1
        }
        lappend output \
            "max_${s}_${p}.value $max" \
            "current_${s}_${p}.value $current" \
            "busy_${s}_${p}.value $busy"
        incr max_total $max
        incr current_total $current
        incr busy_total $busy
      }
    }
    set threadInfo [ns_info threads]
    set nrthreads [llength $threadInfo]
    foreach t $threadInfo {
      set group [classify_threadname [lindex $t 0]]
      if {[string range $group 0 3] eq "tcl:"} {
        incr count(tcl)
      } else {
        incr count($group)
      }
    }
    #set osthreads [lindex [exec -ignorestderr /bin/ps -o nlwp [pid]] 1]
    #ns_log notice "nrthreads $nrthreads osthreads $nrthreads"

    lappend output \
        "max.value $max_total" \
        "current.value $current_total" \
        "busy.value $busy_total" \
        "nrthreads.value $nrthreads"
    foreach g [array names count] {
      lappend output "$g.value $count($g)"
    }
  }

  "threadcpu" {
    array set tt {writers 0 logwriter 0 sum 0}
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
    set spools [expr {[info command ::bgdelivery] ne "" ? [nsv_array names ::xotcl::THREAD ::bgdelivery] ne "": 0}]
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

ns_return 200 "text/plain" [join $output \r\n ]

#
# Local variables:
#    mode: tcl
#    tcl-indent-level: 2
#    indent-tabs-mode: nil
# End:
