#!/usr/bin/env tclsh
#
# Wildcard-script to monitor the number of locks of a running naviserver instance. 
# To monitor a naviserver instance named "development", link this plugin such as:
#
#    ln /usr/share/munin/node/plugins-contrib/naviserver_locks.nr /etc/munin/node.d/naviserver_development_locks.nr
#
# To configure this plugin put something like the 
# following into /etc/munin/plugin-conf.d/naviserver
#
# [naviserver_*]
#    env.url /SYSTEM/munin?t=
#
# [naviserver_development_*]
#    env.address localhost
#    env.port 8000
#    env.ssl  false
#

lassign [split $argv0 _] . serverName service
array set config {
  address localhost
  port 8000
  ssl  false
  url /SYSTEM/munin?t=
  lockvalues "ns:cache:ns:memoize ns:cache:util_memoize ns:cache:xo_site_nodes"
}

foreach n [array names config] {
  if {[info exists ::env($n)]} {
    # puts "override $n with $::env($n)"
    set config($n) $::env($n)
  }
}
append service &lockvalues=[string map {" " +} $config(lockvalues)]

if {$argv eq "config" } {
  puts "graph_title $serverName Mutex Locks"
  puts "graph_args --base 1000 -l 0"
  puts "graph_category naviserver"
  puts {graph_vlabel locks per ${graph_period}}
  puts "graph_info This graph shows the number of Mutex Locks for Naviserver instance $serverName"
  puts "total.label total"
  puts "total.info Total number of Mutex Locks"
  puts "total.type DERIVE"
  puts "total.min 0"
  foreach s $config(lockvalues) {
     set item [string map {: _ . _} $s]
     puts "$item.label $s"
     puts "$item.info Mutex Locks on $s"
     puts "$item.type DERIVE"
     puts "$item.min 0"
  }
  return
}

if {$config(ssl)} {
  # The following catch is due to a seemingly incorrect setup for tcl in fedora core.
  if {[catch {package req tls}]} {lappend auto_path /usr/lib/tcl8.5; package req tls}
  set f [tls::socket $config(address) $config(port)]
} else {
  set f [socket $config(address) $config(port)]
}
puts $f "GET $config(url)$service HTTP/1.0\n"
flush $f
set content [read $f]
close $f
foreach line [split $content \n] {
   set line [string trim $line]
   if {$line eq ""} {set output 1; continue}
   if {[info exists output]} {puts $line}
}

