This is a set of plugins for munin [1], where most of the plugins
provide monitoring functionality for aolserver [2] and naviserver [3].
Most of the functionality of the naviserver* plugins depends on the
XOTcl request monitor package, which is part of OpenACS [4].

To install the plugins (the files in the plugins directory), place 
these into your local munin plugin directory (such as

    /usr/local/munin/lib/plugins
    /usr/share/munin/node/plugins-contrib/

whatever you have on your system, differs from distribution to
distribution, can be locally configured) or into the "official" munin
plugin directory

    /usr/share/munin/plugins/
    /opt/local/lib/munin/plugins/ (Mac OS X)

where you should have already a large set of plugins provided by
munin.  Be aware that upgrades might overwrite existing plugin scripts
with newer versions from the distribution, but that should be no issue
for the naviserver* plugins as long they are not included in a general
distribution.

The munin plugins are typically activated by adding links from
the plugin source files to 

    /etc/munin/plugins/
    /opt/local/etc/munin/plugins (Mac OS X)

Since one might have multiple instances of naviserver running, the
links might contain names for distinguishing these. In order to
activate a the plugin "naviserver_locks.busy" for a server named
"development", one might use the following link

  ln -s /usr/share/munin/node/plugins-contrib/naviserver_locks.busy \
     /etc/munin/plugins/naviserver_development_locks.busy

One can automize the linking steps by using the following snippet for
the chosen plugins

  set plugins="threadcpu serverstats lsof users24 responsetime views users threads memsize"
  set host="development"

  for plugin in $plugins; do
    set source /usr/share/munin/plugins/naviserver_$plugin
    set target /etc/munin/plugins/naviserver_${host}_$plugin
	ln -sf $source $target 
  done



Furthermore, the interface script for aolserver and/or naviserver
provided in the subdirectory tcl is needed to be placed at an
accessible url path of the web server (e.g. under the URL
/SYSTEM/munin.tcl).


Requirements:

The plugins require Tcl 8.5 to be installed and work with
both aolserver (e.g. 4.5.1) and naviserver (e.g. 4.99.6).


Configuration:

The plugins can be configured via the file 

  /etc/munin/plugin-conf.d/naviserver

where default values can be specified. One can
specify the url-path leading to the interface script,
as well as the hostname an port of the server.

 [naviserver_*]
    env.url /SYSTEM/munin?t=

 [naviserver_development_*]
    env.address localhost
    env.port 8000

Consult the plugins for further plugin-specific
configurations

After configuration, you should restart
the munin-node, e.g. on an Ubuntu system with

    service munin-node restart

One can check, if a plugin returns a valid value via
a call like for a server named "development":

     munin-run naviserver_development_users



-gustaf neumann        (Feb 2015)


[1] http://munin-monitoring.org/
[2] http://www.aolserver.com/
[3] http://sourceforge.net/projects/naviserver/
[4] http://openacs.org/

