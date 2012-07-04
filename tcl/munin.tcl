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
       lappend output "[string map {: _} $s].value [expr {int($lockvalue($s)*$scale)}]"
    }
    return $output
}
	
switch [ns_queryget t ""] {

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
         lappend output "[string map {: _} $v].value $c"
       }
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
        set sizes [exec /bin/ps -o vsize,rss [pid]]
        lappend output \
	    "vsize.value [expr {[lindex $sizes end-1]*1024}]" \
	    "rss.value [expr {[lindex $sizes end]*1024}]"
       
    }
    "locks.nr"   { set output [mutex_sum nlock 1] }
    "locks.busy" { set output [mutex_sum nbusy 1] }
    "locks.wait" { set output [mutex_sum totalWait 1000] }

    "threads" {
        #min 1 max 30 current 6 idle 5 stopping 0
        array set thread_info [throttle do throttle server_threads]
        set rspools [expr {[info command ::bgdelivery] ne "" ? [bgdelivery nr_running] : 0}]
        lappend output \
	    "max.value $thread_info(max)" \
            "current.value $thread_info(current)" \
            "busy.value [expr {$thread_info(current) - $thread_info(idle) - 1}]" \
            "nrthreads.value [lindex [exec /bin/ps -o nlwp [pid]] 1]" \
            "rspools.value $rspools"
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
              "alt_views.value [throttle do set ::threads_datapoints]" \
              "spools.value $spools"
        }
    }
    default {
       lappend  output "unknown.value 0"
    }

}

ns_return 200 "text/plain" [join $output \r ]

