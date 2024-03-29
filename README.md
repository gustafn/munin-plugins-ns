This is a set of plugins for munin [1], where most of the plugins
provide monitoring functionality for AOLserver [2] and NaviServer [3].
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
    /opt/local/lib/munin/plugins/ (macOS)

where you should have already a large set of plugins provided by
munin.  Be aware that upgrades might overwrite existing plugin scripts
with newer versions from the distribution, but that should be no issue
for the naviserver* plugins as long they are not included in a general
distribution.

The munin plugins are typically activated by adding links from
the plugin source files to 

    /etc/munin/plugins/
    /opt/local/etc/munin/plugins (macOS)

Since one might have multiple instances of NaviServer running, the
links might contain names for distinguishing these. In order to
activate the plugin "naviserver_locks.busy" for a server named
"development", one might use the following link

    ln -s /usr/share/munin/node/plugins-contrib/naviserver_locks.busy \
       /etc/munin/plugins/naviserver_development_locks.busy

One can automize the linking steps by using the following snippet for
the chosen plugins

    plugins="locks.busy locks.nr locks.wait logstats lsof memsize \
        responsetime serverstats threadcpu threads users users24 views"
    host="development"

    for plugin in $plugins; do
      source=/usr/share/munin/plugins/naviserver_$plugin
      target=/etc/munin/plugins/naviserver_${host}_$plugin
	  ln -sf $source $target
    done


Furthermore, the interface script for AOLserver and/or NaviServer
provided in the subdirectory tcl is needed to be placed at an
accessible url path of the web server (e.g. under the URL
/SYSTEM/munin.tcl).


Requirements:
-------------

The plugins require Tcl 8.6 to be installed and work with
both AOLserver (e.g. 4.5.1) and NaviServer (e.g. 4.99.6) or newer.

Configuration:
--------------

The plugins can be configured via the file 

    /etc/munin/plugin-conf.d/naviserver

where default values can be specified. One can
specify the url-path leading to the interface script,
as well as the hostname an port of the server.

    [naviserver_*]
       env.url /SYSTEM/munin.tcl?t=

    [naviserver_development_*]
       env.address localhost
       env.port 8000

Consult the plugins for further plugin-specific
configurations

After configuration, you should restart
the munin-node, e.g. on an Ubuntu/RedHat system with

    service munin-node restart

One can check, if a plugin returns a valid value via
a call like for a server named "development":

    munin-run naviserver_development_users



-gustaf neumann        (Feb 2015)


[1] http://munin-monitoring.org/  
[2] http://www.aolserver.com/  
[3] http://sourceforge.net/projects/naviserver/  
[4] http://openacs.org/  

