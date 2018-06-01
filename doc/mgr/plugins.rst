
ceph-mgr plugin author guide
============================

Creating a plugin
-----------------

In pybind/mgr/, create a python module.  Within your module, create a class
that inherits from ``MgrModule``.

The most important methods to override are:

* a ``serve`` member function for server-type modules.  This
  function should block forever.
* a ``notify`` member function if your module needs to
  take action when new cluster data is available.
* a ``handle_command`` member function if your module
  exposes CLI commands.

Installing a plugin
-------------------

Once your module is present in the location set by the
``mgr module path`` configuration setting, you can enable it
via the ``ceph mgr module enable`` command::

  ceph mgr module enable mymodule

Note that the MgrModule interface is not stable, so any modules maintained
outside of the Ceph tree are liable to break when run against any newer
or older versions of Ceph.

Logging
-------

``MgrModule`` instances have a ``log`` property which is a logger instance that
sends log messages into the Ceph logging layer where they will be recorded
in the mgr daemon's log file.

Use it the same way you would any other python logger.  The python
log levels debug, info, warn, err are mapped into the Ceph
severities 20, 4, 1 and 0 respectively.

Exposing commands
-----------------

Set the ``COMMANDS`` class attribute of your plugin to a list of dicts
like this::

    COMMANDS = [
        {
            "cmd": "foobar name=myarg,type=CephString",
            "desc": "Do something awesome",
            "perm": "rw",
            # optional:
            "poll": "true"
        }
    ]

The ``cmd`` part of each entry is parsed in the same way as internal
Ceph mon and admin socket commands (see mon/MonCommands.h in
the Ceph source for examples). Note that the "poll" field is optional,
and is set to False by default.

Configuration options
---------------------

Modules can load and store configuration options using the
``set_config`` and ``get_config`` methods.

.. note:: Use ``set_config`` and ``get_config`` to manage user-visible
   configuration options that are not blobs (like certificates). If you want to
   persist module-internal data or binary configuration data consider using
   the `KV store`_.

You must declare your available configuration options in the
``OPTIONS`` class attribute, like this:

::

    OPTIONS = [
        {
            "name": "my_option"
        }
    ]

If you try to use set_config or get_config on options not declared
in ``OPTIONS``, an exception will be raised.

You may choose to provide setter commands in your module to perform
high level validation.  Users can also modify configuration using
the normal `ceph config set` command, where the configuration options
for a mgr module are named like `mgr/<module name>/<option>`.

If a configuration option is different depending on which node
the mgr is running on, then use *localized* configuration (
``get_localized_config``, ``set_localized_config``).  This may be necessary
for options such as what address to listen on.  Localized options may
also be set externally with ``ceph config set``, where they key name
is like ``mgr/<module name>/<mgr id>/<option>``

If you need to load and store data (e.g. something larger, binary, or multiline),
use the KV store instead of configuration options (see next section).

Hints for using config options:

* Reads are fast: ceph-mgr keeps a local in-memory copy, so in many cases
  you can just do a get_config every time you use a option, rather than
  copying it out into a variable.
* Writes block until the value is persisted (i.e. round trip to the monitor),
  but reads from another thread will see the new value immediately.
* If a user has used `config set` from the command line, then the new
  value will become visible to `get_config` immediately, although the
  mon->mgr update is asynchronous, so `config set` will return a fraction
  of a second before the new value is visible on the mgr.
* To delete a config value (i.e. revert to default), just pass ``None`` to
  set_config.

.. py:currentmodule:: mgr_module
.. automethod:: MgrModule.get_config
.. automethod:: MgrModule.set_config
.. automethod:: MgrModule.get_localized_config
.. automethod:: MgrModule.set_localized_config

KV store
--------

Modules have access to a private (per-module) key value store, which
is implemented using the monitor's "config-key" commands.  Use
the ``set_store`` and ``get_store`` methods to access the KV store from
your module.

The KV store commands work in a similar way to the configuration
commands.  Reads are fast, operating from a local cache.  Writes block
on persistence and do a round trip to the monitor.

This data can be access from outside of ceph-mgr using the
``ceph config-key [get|set]`` commands.  Key names follow the same
conventions as configuration options.  Note that any values updated
from outside of ceph-mgr will not be seen by running modules until
the next restart.  Users should be discouraged from accessing module KV
data externally -- if it is necessary for users to populate data, modules
should provide special commands to set the data via the module.

Use the ``get_store_prefix`` function to enumerate keys within
a particular prefix (i.e. all keys starting with a particular substring).


.. automethod:: MgrModule.get_store
.. automethod:: MgrModule.set_store
.. automethod:: MgrModule.set_store_json
.. automethod:: MgrModule.get_store_json
.. automethod:: MgrModule.get_localized_store
.. automethod:: MgrModule.set_localized_store
.. automethod:: MgrModule.get_store_prefix


Accessing cluster data
----------------------

Modules have access to the in-memory copies of the Ceph cluster's
state that the mgr maintains.  Accessor functions as exposed
as members of MgrModule.

Calls that access the cluster or daemon state are generally going
from Python into native C++ routines.  There is some overhead to this,
but much less than for example calling into a REST API or calling into
an SQL database.

There are no consistency rules about access to cluster structures or
daemon metadata.  For example, an OSD might exist in OSDMap but
have no metadata, or vice versa.  On a healthy cluster these
will be very rare transient states, but plugins should be written
to cope with the possibility.

Note that these accessors must not be called in the modules ``__init__``
function. This will result in a circular locking exception.

.. automethod:: MgrModule.get
.. automethod:: MgrModule.get_server
.. automethod:: MgrModule.list_servers
.. automethod:: MgrModule.get_metadata
.. automethod:: MgrModule.get_counter

What if the mons are down?
--------------------------

The manager daemon gets much of its state (such as the cluster maps)
from the monitor.  If the monitor cluster is inaccessible, whichever
manager was active will continue to run, with the latest state it saw
still in memory.

However, if you are creating a module that shows the cluster state
to the user then you may well not want to mislead them by showing
them that out of date state.

To check if the manager daemon currently has a connection to
the monitor cluster, use this function:

.. automethod:: MgrModule.have_mon_connection

Reporting if your module cannot run
-----------------------------------

If your module cannot be run for any reason (such as a missing dependency),
then you can report that by implementing the ``can_run`` function.

.. automethod:: MgrModule.can_run

Note that this will only work properly if your module can always be imported:
if you are importing a dependency that may be absent, then do it in a
try/except block so that your module can be loaded far enough to use
``can_run`` even if the dependency is absent.

Sending commands
----------------

A non-blocking facility is provided for sending monitor commands
to the cluster.

.. automethod:: MgrModule.send_command


Implementing standby mode
-------------------------

For some modules, it is useful to run on standby manager daemons as well
as on the active daemon.  For example, an HTTP server can usefully
serve HTTP redirect responses from the standby managers so that
the user can point his browser at any of the manager daemons without
having to worry about which one is active.

Standby manager daemons look for a subclass of ``StandbyModule``
in each module.  If the class is not found then the module is not
used at all on standby daemons.  If the class is found, then
its ``serve`` method is called.  Implementations of ``StandbyModule``
must inherit from ``mgr_module.MgrStandbyModule``.

The interface of ``MgrStandbyModule`` is much restricted compared to
``MgrModule`` -- none of the Ceph cluster state is available to
the module.  ``serve`` and ``shutdown`` methods are used in the same
way as a normal module class.  The ``get_active_uri`` method enables
the standby module to discover the address of its active peer in
order to make redirects.  See the ``MgrStandbyModule`` definition
in the Ceph source code for the full list of methods.

For an example of how to use this interface, look at the source code
of the ``dashboard`` module.

Logging
-------

Use your module's ``log`` attribute as your logger.  This is a logger
configured to output via the ceph logging framework, to the local ceph-mgr
log files.

Python log severities are mapped to ceph severities as follows:

* DEBUG is 20
* INFO is 4
* WARN is 1
* ERR is 0

Shutting down cleanly
---------------------

If a module implements the ``serve()`` method, it should also implement
the ``shutdown()`` method to shutdown cleanly: misbehaving modules
may otherwise prevent clean shutdown of ceph-mgr.

Limitations
-----------

It is not possible to call back into C++ code from a module's
``__init__()`` method.  For example calling ``self.get_config()`` at
this point will result in an assertion failure in ceph-mgr.  For modules
that implement the ``serve()`` method, it usually makes sense to do most
initialization inside that method instead.

Is something missing?
---------------------

The ceph-mgr python interface is not set in stone.  If you have a need
that is not satisfied by the current interface, please bring it up
on the ceph-devel mailing list.  While it is desired to avoid bloating
the interface, it is not generally very hard to expose existing data
to the Python code when there is a good reason.

