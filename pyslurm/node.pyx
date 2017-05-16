# cython: embedsignature=True
# cython: cdivision=True
"""
===========
:mod:`node`
===========

The node extension module is used to get Slurm node information.

Slurm API Functions
-------------------

This module declares and wraps the following Slurm API functions:

- slurm_free_node_info_msg
- slurm_get_select_nodeinfo
- slurm_init_update_node_msg
- slurm_load_node
- slurm_load_node_single
- slurm_make_time_str
- slurm_node_state_string
- slurm_print_node_info_msg
- slurm_print_node_table
- slurm_update_node

Node Objects
------------

Several functions in this module wrap the ``node_info_t`` struct found in
`slurm.h`. The members of this struct are converted to a :class:`Node` object,
which implements Python properties to retrieve the value of each attribute.

Each node record in a ``node_info_msg_t`` struct is converted to a
:class:`Node` object when calling some of the functions in this module.

"""
from __future__ import absolute_import, division, unicode_literals

import os as _os
from pwd import getpwuid

from libc.stdio cimport stdout
from .c_node cimport *
from .slurm_common cimport *
from .utils cimport *
from .exceptions import PySlurmError

include "node.pxi"

cdef class Node:
    """An object to wrap `node_info_t` structs."""
    cdef:
        readonly uint64_t alloc_mem
        readonly unicode alloc_tres
        readonly object arch
        readonly uint16_t boards
        readonly time_t boot_time
        readonly unicode boot_time_str
        uint32_t cap_watts
        readonly unicode cfg_tres
        uint64_t consumed_joules
        readonly uint16_t cores_per_socket
        readonly uint16_t core_spec_cnt
        uint32_t cpu_load
        readonly uint16_t cpu_alloc
        readonly uint16_t cpu_err
        readonly uint16_t cpu_tot
        readonly unicode cpu_spec_list
        uint32_t current_watts
        uint64_t ext_sensors_joules
        uint64_t ext_sensors_temp
        uint64_t ext_sensors_watts
        readonly list available_features
        readonly list active_features
        uint32_t free_mem
        readonly list gres
        readonly list gres_drain
        readonly list gres_used
        uint32_t lowest_joules
        readonly uint64_t mem_spec_limit
        readonly unicode node_name
        readonly unicode node_addr
        readonly unicode node_host_name
        readonly unicode os
        uint32_t owner
        readonly unicode partitions
        readonly uint64_t real_memory
        readonly unicode rack_midplane
        readonly unicode reason
        readonly unicode reason_str
        readonly time_t reason_time
        readonly unicode reason_time_str
        readonly uint32_t reason_uid
        readonly unicode reason_user
        readonly time_t slurmd_start_time
        readonly unicode slurmd_start_time_str
        readonly uint16_t sockets
        readonly unicode state
        readonly uint16_t threads_per_core
        readonly uint32_t tmp_disk
        readonly unicode version
        readonly uint32_t weight

    @property
    def cap_watts(self):
        """Power consumption limit of node (watts)"""
        if self.cap_watts == NO_VAL:
            return "n/a"
        else:
            return self.cap_watts

    @property
    def consumed_joules(self):
        """
        Energy consumed by node between the time registered by slurmd (joules,
        n/s if not supported)
        """
        if self.consumed_joules == NO_VAL:
            return "n/s"
        else:
            return int(self.consumed_joules)

    @property
    def cpu_load(self):
        """CPU load"""
        if self.cpu_load == NO_VAL:
            return "N/A"
        else:
            return "%.2f" % (self.cpu_load / 100.0)

    @property
    def current_watts(self):
        """Instantaneous power consumption of node (watts)"""
        if self.current_watts == NO_VAL:
            return "n/s"
        else:
            return self.current_watts

    @property
    def ext_sensors_joules(self):
        """
        Energy consumed by node since time powered on (joules, n/s if not
        supported)
        """
        if self.ext_sensors_joules == NO_VAL:
            return "n/s"
        else:
            return int(self.ext_sensors_joules)

    @property
    def ext_sensors_temp(self):
        """Temperature of node (joules, n/s if not supported)"""
        if self.ext_sensors_temp == NO_VAL:
            return "n/s"
        else:
            return int(self.ext_sensors_temp)

    @property
    def ext_sensors_watts(self):
        """
        Instantaneous power consumption of node (joules, n/s if not supported)
        """
        if self.ext_sensors_watts == NO_VAL:
            return "n/s"
        else:
            return int(self.ext_sensors_watts)

    @property
    def free_mem(self):
        """Free memory in MiB"""
        if self.free_mem == NO_VAL64:
            return "N/A"
        else:
            return self.free_mem

    @property
    def lowest_joules(self):
        """
        Energy consumed by node between time powered on and time registered
        with slurmd (joules, n/s if not supported)
        """
        if self.lowest_joules == NO_VAL:
            return "n/s"
        else:
            return int(self.lowest_joules)

    @property
    def owner(self):
        """User allowed to use this node or NO_VAL"""
        if self.owner == NO_VAL:
            return "N/A"
        else:
            return self.owner


def get_nodes(ids=False):
    """
    Return a list of all :class:`Node` objects.

    This function calls ``slurm_load_node`` to retrieve information for all
    nodes.

    Args:
        ids (Optional[bool]): Return list of only node names if True (default
            False).
    Returns:
        list: A list of :class:`Node` objects, one for each configured node in the
            cluster.
    Raises:
        PySlurmError: if ``slurm_load_node`` is unsuccessful.

    """
    return get_node_info_msg(None, ids)


def get_node(node):
    """
    Return a single :class:`Node` object for the given node.

    This function calls `slurm_load_node_single` to retrieve information for
    the given node.

    Args:
        node (str): node to query
    Returns:
        Node: A single :class:`Node` object
    Raises:
        PySlurmError: If ``slurm_load_node_single`` is unsuccessful.

    """
    return get_node_info_msg(node)


cdef get_node_info_msg(node, ids=False):
    """Return one or more Node objects.

    This function calls either slurm_load_node or slurm_load_node_single to
    return :class:`Node` objects.  ``slurm_load_node_single`` will return a
    single :class:`Node` object, whereas ``slurm_load_node`` will return all
    :class:`Node` objects, one for each node configured in the cluster.

    If node is NULL, then call ``slurm_load_node`` to get all nodes.  If node
    is not NULL, then call ``slurm_load_node_single`` to get specific node.

    This function wraps the ``slurm_sprint_node_table`` function found in
    `src/api/node_info.c`.

    Args:
        node (str): node id to query.  If node is None, then get all nodes.
        ids (Optional[bool]): True returns only the node names (default
            False).
    Returns:
        A single node object or a list of all :class:`Node` objects
    Raises:
        PySlurmError: If ``slurm_load_node`` or ``slurm_load_node_single`` is
            unsuccessful.

    """
    cdef:
        node_info_msg_t *node_info_msg_ptr = NULL
        uint16_t show_flags = SHOW_ALL | SHOW_DETAIL
        int cpus_per_node = 1
        int idle_cpus
        int inx
        int rc
        int total_used
        char* cloud_str = ""
        char* comp_str = ""
        char* drain_str = ""
        char* node_alloc_tres = NULL
        char* power_str = ""
        char* reason_str = NULL
        char* select_reason_str = NULL
        char time_str[32]
        char* save_ptr = NULL
        char* tok
        char* user_name
        uint16_t err_cpus = 0
        uint16_t alloc_cpus = 0
        uint32_t i
        uint64_t alloc_memory
        uint32_t my_state
        uint32_t cluster_flags = slurmdb_setup_cluster_flags()

    if node is None:
        rc = slurm_load_node(<time_t>NULL, &node_info_msg_ptr, show_flags)
    else:
        b_node = node.encode("UTF-8")
        rc = slurm_load_node_single(&node_info_msg_ptr, b_node, show_flags)

    node_list = []
    if rc == SLURM_SUCCESS:
        for record in node_info_msg_ptr.node_array[:node_info_msg_ptr.record_count]:

            if ids and node is None:
                node_list.append(tounicode(record.name))
                continue

            my_state = record.node_state

            if node_info_msg_ptr.node_scaling:
                cpus_per_node = record.cpus / node_info_msg_ptr.node_scaling

            if (my_state & NODE_STATE_CLOUD):
                my_state &= (~NODE_STATE_CLOUD)
                cloud_str = "+CLOUD"

            if (my_state & NODE_STATE_COMPLETING):
                my_state &= (~NODE_STATE_COMPLETING)
                comp_str = "+COMPLETING"

            if (my_state & NODE_STATE_DRAIN):
                my_state &= (~NODE_STATE_DRAIN)
                drain_str = "+DRAIN"

            if (my_state & NODE_STATE_FAIL):
                my_state &= (~NODE_STATE_FAIL)
                drain_str = "+FAIL"

            if (my_state & NODE_STATE_POWER_SAVE):
                my_state &= (~NODE_STATE_POWER_SAVE)
                power_str = "+POWER"

            slurm_get_select_nodeinfo(record.select_nodeinfo,
                                      SELECT_NODEDATA_SUBCNT,
                                      NODE_STATE_ALLOCATED,
                                      &alloc_cpus)

            if (cluster_flags & CLUSTER_FLAG_BG):
                if (not alloc_cpus and
                    (IS_NODE_ALLOCATED(record) or
                     IS_NODE_COMPLETING(record))):
                    alloc_cpus = record.cpus
                else:
                    alloc_cpus *= cpus_per_node

            idle_cpus = record.cpus - alloc_cpus

            slurm_get_select_nodeinfo(record.select_nodeinfo,
                                      SELECT_NODEDATA_SUBCNT,
                                      NODE_STATE_ERROR,
                                      &err_cpus)

            if (cluster_flags & CLUSTER_FLAG_BG):
                err_cpus *= cpus_per_node

            idle_cpus -= err_cpus

            if (alloc_cpus and err_cpus) or (idle_cpus and
                   (idle_cpus != record.cpus)):
                    my_state &= NODE_STATE_FLAGS
                    my_state |= NODE_STATE_MIXED

            # Instantiate empty Node class instance for storing attributes
            this_node = Node()

            this_node.node_name = tounicode(record.name)

            if (cluster_flags & CLUSTER_FLAG_BG):
                slurm_get_select_nodeinfo(record.select_nodeinfo,
                                          SELECT_NODEDATA_RACK_MP,
                                          <node_states>0, &select_reason_str)
                if select_reason_str:
                    this_node.rack_midplane = tounicode(select_reason_str)

            if record.arch:
                this_node.arch = tounicode(record.arch)

            this_node.cores_per_socket = record.cores
            this_node.cpu_alloc = alloc_cpus
            this_node.cpu_err = err_cpus
            this_node.cpu_tot = record.cpus
            this_node.cpu_load = record.cpu_load
            this_node.available_features = tounicode(record.features).split(",")
            this_node.active_features = tounicode(record.features_act).split(",")
            this_node.gres = tounicode(record.gres).split(",")

            if record.gres_drain:
                this_node.gres_drain = tounicode(record.gres_drain).split(",")

            if record.gres_used:
                this_node.gres_used = tounicode(record.gres_used).split(",")

            if record.node_hostname or record.node_addr:
                this_node.node_addr = tounicode(record.node_addr)
                this_node.node_host_name = tounicode(record.node_hostname)
                this_node.version = tounicode(record.version)

            if record.os:
                this_node.os = tounicode(record.os)

            slurm_get_select_nodeinfo(record.select_nodeinfo,
                                      SELECT_NODEDATA_MEM_ALLOC,
                                      NODE_STATE_ALLOCATED,
                                      &alloc_memory)

            this_node.real_memory = record.real_memory
            this_node.alloc_mem = alloc_memory
            this_node.free_mem = record.free_mem
            this_node.sockets = record.sockets
            this_node.boards = record.boards

            # Core and Memory Specialization
            if (record.core_spec_cnt or record.cpu_spec_list or
                record.mem_spec_limit):
                if record.core_spec_cnt:
                    this_node.core_spec_count = record.core_spec_cnt
                if record.cpu_spec_list:
                    this_node.cpu_spec_list = tounicode(
                        record.cpu_spec_list
                    ).split(",")
                if record.mem_spec_limit:
                    this_node.mem_spec_limit = record.mem_spec_limit

            # Line
            this_node.state = (tounicode(slurm_node_state_string(my_state)) +
                               tounicode(cloud_str) +
                               tounicode(comp_str) +
                               tounicode(drain_str) +
                               tounicode(power_str))

            this_node.threads_per_core = record.threads
            this_node.tmp_disk = record.tmp_disk
            this_node.weight = record.weight
            this_node.owner = record.owner

            # Line
            if record.partitions:
                this_node.partitions = tounicode(record.partitions)

            # Line
            if record.boot_time:
                this_node.boot_time = record.boot_time
                slurm_make_time_str(<time_t *>&record.boot_time,
                                    time_str, sizeof(time_str))
                b_time_str = time_str
                this_node.boot_time_str = tounicode(b_time_str)

            if record.slurmd_start_time:
                this_node.slurmd_start_time = record.slurmd_start_time
                slurm_make_time_str(<time_t *>&record.slurmd_start_time,
                                    time_str, sizeof(time_str))
                b_time_str = time_str
                this_node.slurmd_start_time_str = tounicode(b_time_str)

            # TRES line
            slurm_get_select_nodeinfo(record.select_nodeinfo,
                                      SELECT_NODEDATA_TRES_ALLOC_FMT_STR,
                                      NODE_STATE_ALLOCATED, &node_alloc_tres)
            if record.tres_fmt_str:
                this_node.cfg_tres = tounicode(record.tres_fmt_str)
            if node_alloc_tres != NULL:
                this_node.alloc_tres = tounicode(node_alloc_tres)
                # TODO:
                # xfree(node_alloc_tres)
            else:
                this_node.alloc_tres = tounicode("")

            # Power Management Line
            if (not record.power or (record.power.cap_watts == NO_VAL)):
                this_node.cap_watts = NO_VAL
            else:
                this_node.cap_watts = record.power.cap_watts

            # Power Consumption Line
            if (not record.energy or (record.energy.current_watts == NO_VAL)):
                this_node.current_watts = NO_VAL
                this_node.lowest_joules = NO_VAL
                this_node.consumed_joules = NO_VAL
            else:
                this_node.current_watts = record.energy.current_watts
                this_node.lowest_joules = record.energy.base_consumed_energy
                this_node.consumed_joules = record.energy.consumed_energy

            # External Sensors
            if (not record.ext_sensors or (
                    record.ext_sensors.consumed_energy == NO_VAL)):
                this_node.ext_sensors_joules = NO_VAL
            else:
                this_node.ext_sensors_joules = record.ext_sensors.consumed_energy

            if (not record.ext_sensors or (
                    record.ext_sensors.current_watts == NO_VAL)):
                this_node.ext_sensors_watts = NO_VAL
            else:
                this_node.ext_sensors_watts = record.ext_sensors.current_watts

            if (not record.ext_sensors or (
                    record.ext_sensors.temperature == NO_VAL)):
                this_node.ext_sensors_temp = NO_VAL
            else:
                this_node.ext_sensors_temp = record.ext_sensors.temperature

            if record.reason and record.reason[0]:
                this_node.reason = tounicode(record.reason)
                reason_str = record.reason
                u_reason_str = tounicode(reason_str)

            slurm_get_select_nodeinfo(record.select_nodeinfo,
                                      SELECT_NODEDATA_EXTRA_INFO,
                                      <node_states>0, &select_reason_str)

            if select_reason_str and select_reason_str[0]:
                u_select_reason_str = tounicode(select_reason_str)
                if u_reason_str:
                    u_reason_str += "\n"
                u_reason_str += u_select_reason_str

            if reason_str and record.reason_time:
                slurm_make_time_str(<time_t *>&record.reason_time,
                                    time_str, sizeof(time_str))

                try:
                    # getpwuid returns str, not bytes; we want unicode
                    u_reason_user = unicode(getpwuid(record.reason_uid)[0])
                except KeyError:
                    b_reason_user = <bytes>record.reason_uid
                    u_reason_user = tounicode(b_reason_user)

                this_node.reason_user = u_reason_user

                b_time_str = time_str
                this_node.reason_time_str = tounicode(b_time_str)

                u_reason_str += (" [" + u_reason_user +
                                 "@" + tounicode(b_time_str) + "]")

                this_node.reason_str = u_reason_str
                this_node.reason_uid = record.reason_uid
                this_node.reason_time = record.reason_time

            node_list.append(this_node)

        slurm_free_node_info_msg(node_info_msg_ptr)
        node_info_msg_ptr = NULL

        if node is None:
            return node_list
        else:
            return this_node
    else:
        raise PySlurmError(slurm_strerror(rc), rc)


cpdef print_node_info_msg(int one_liner=False):
    """
    Print information about all nodes to stdout.

    This function outputs information about all Slurm nodes based upon the
    message loaded by ``slurm_load_node``. It uses the
    ``slurm_print_node_info_msg`` function to print to stdout. The output is
    equivalent to *scontrol show node*.

    Args:
        one_liner (Optional[bool]): print each node on one line if True
            (default False)
    Raises:
        PySlurmError: If ``slurm_load_node`` is not successful.

    """
    cdef:
        node_info_msg_t* node_info_msg_ptr = NULL
        uint16_t show_flags = SHOW_ALL | SHOW_DETAIL
        int rc

    rc = slurm_load_node(<time_t>NULL, &node_info_msg_ptr, show_flags)

    if rc == SLURM_SUCCESS:
        slurm_print_node_info_msg(stdout, node_info_msg_ptr, one_liner)
        slurm_free_node_info_msg(node_info_msg_ptr)
        node_info_msg_ptr = NULL
    else:
        raise PySlurmError(slurm_strerror(rc), rc)


cpdef print_node_info_table(node, int one_liner=False):
    """
    Print information about a specific node to stdout.

    This function outputs information about a give Slurm node based upon the
    message loaded by ``slurm_load_node_single``. It uses the
    ``slurm_print_node_table`` function to print to stdout.  The output is
    equivalent to *scontrol show node <nodename>*

    Args:
        node (str): print single node
        one_liner (Optional[bool]): print single node on one line if True
            (default False)
    Raises:
        PySlurmError: If ``slurm_load_node_single`` is not successful.
    """
    cdef:
        node_info_msg_t *node_info_msg_ptr = NULL
        uint16_t show_flags = SHOW_ALL | SHOW_DETAIL
        int rc

    b_node = node.encode("UTF-8")
    rc = slurm_load_node_single(&node_info_msg_ptr, b_node, show_flags)

    if rc == SLURM_SUCCESS:
        slurm_print_node_table(stdout, &node_info_msg_ptr.node_array[0],
                               node_info_msg_ptr.node_scaling, one_liner)
        slurm_free_node_info_msg(node_info_msg_ptr)
        node_info_msg_ptr = NULL
    else:
        raise PySlurmError(slurm_strerror(rc), rc)


# NOTE: Should this return a generator instead of a list of Node objects?
def find_nodes(nodeattr, pattern, ids=False):
    """
    Return all nodes where an attribute matches pattern.

    This is a PySlurm convenience function that will search all nodes where the
    node attribute matches the pattern string.

    Args:
        nodeattr (str): node attribute to compare
        pattern (str): pattern to search for in the node attribute
        ids (Optional[bool]): If True, return only the node names. Otherwise,
            return the full :class:`Node` object for each matched node (default False)

    Returns:
        list: A list of matched nodes.

    Examples:
        Returns a list of node names if `ids` is set to True:

            >>> from pyslurm import node
            >>> node.find_nodes("state", "MIXED", ids=True)
            >>> ['c1', 'c4', 'c9']

        Returns a list of :class:`Node` objects if `ids` is False:

            >>> from pyslurm import node
            >>> node.find_nodes("state", "MIXED")
            >>> [<pyslurm.node.Node object at 0xe0af60>, <pyslurm.node.Node
            object at 0xdc17b0>, <pyslurm.node.Node object at 0xdc1900>]

    Note:
        The pattern string is case sensitive.  For example, **MIXED** is not
        the same as **mixed** and would return an empty list.

    """
    matched_nodes = []
    try:
        all_nodes = get_nodes()
    except:
        raise

    for node_obj in all_nodes:
        try:
            if pattern in getattr(node_obj, nodeattr):
                if ids == False:
                    matched_nodes.append(node_obj)
                else:
                    matched_nodes.append(node_obj.node_name)
        except:
            continue

    return matched_nodes


cpdef int update_node(dict node_dict):
    """
    Request that the state of one or more nodes be updated.

    This function uses ``slurm_update_node`` to update the state of one or more
    nodes.  The available node states are defined in `slurm.h`, although, the
    values most likely to be used are:

        - NODE_STATE_DRAIN
        - NODE_STATE_FAIL
        - NODE_RESUME

    Valid keys in the supplied `node_dict` are:

        - node_names `(mandatory)`
        - node_state `(mandatory)`
        - gres
        - reason
        - node_addr
        - node_hostname
        - features
        - reason
        - weight


    Args:
        node_dict (dict): Dictionary of node parameters to update.

    Returns:
        int: Slurm return code.

    Raises:
        PySlurmError: If ``slurm_update_node`` is unsuccessful.

    Example:

        >>> from pyslurm import node
        >>> from pyslurm.node import NODE_STATE_DRAIN
        >>> update_msg = {
        ...    "node_names": "c[1-3]",
        ...    "reason": "Maintenance",
        ...    "node_state": NODE_STATE_DRAIN,
        ... }
        >>> node.update_node(update_msg)
        0

    Notes:
        #. This method requires **root** privileges.
        #. Use :func:`get_errno` to translate return code if not 0.

    """
    cdef:
        update_node_msg_t update_node_msg
        int rc
        int errno

    if not node_dict:
        raise PySlurmError("You must provide a node update dictionary.")

    slurm_init_update_node_msg(&update_node_msg)

    if "features" in node_dict:
        update_node_msg.features = node_dict["features"]

    if "gres" in node_dict:
        update_node_msg.gres = node_dict["gres"]

    # Optional
    if "node_addr" in node_dict:
        update_node_msg.node_addr = node_dict["node_addr"]

    # Optional
    if "node_hostname" in node_dict:
        update_node_msg.node_hostname = node_dict["node_hostname"]

    if "node_names" in node_dict:
        update_node_msg.node_names = node_dict["node_names"]

    if "node_state" in node_dict:
        update_node_msg.node_state = <uint32_t>node_dict["node_state"]

    if "reason" in node_dict:
        update_node_msg.reason = node_dict["reason"]
        update_node_msg.reason_uid = <uint32_t>_os.getuid()

    if "weight" in node_dict:
        update_node_msg.weight = <uint32_t>node_dict["weight"]

    rc = slurm_update_node(&update_node_msg)

    if rc != SLURM_SUCCESS:
        errno = slurm_get_errno()
        raise PySlurmError(slurm_strerror(errno), errno)
    else:
        return rc
