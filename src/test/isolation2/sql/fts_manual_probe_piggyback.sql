-- See src/backend/fts/README for background information
--
-- Piggyback Test
-- Ensure multiple probe requests come in before the start of a new ftsLoop,
-- then all those requests share the same result.
--
-- It is useful to remember that the FtsLoop and each FtsNotifyProbe are
-- individual processes. Careful use of fault injectors are needed to have
-- complete and consistent control over the flow of the two independent
-- processes - the ftsLoop and FtsNotifyProber's.

include: helpers/server_helpers.sql;

create extension if not exists gp_inject_fault;
select gp_inject_fault('all', 'reset', 1);

-- ensure the internal regular probes do not affect our test
!\retcode gpconfig -c gp_fts_probe_interval -v 3600;
!\retcode gpstop -u;

-- ensure there is no in progress ftsLoop after reloading the gp_fts_probe_interval
select gp_request_fts_probe_scan();

-- start counting number of probe requests
select gp_inject_fault_infinite('ftsNotify_before', 'skip', 1);

-- ensure the ftsLoop is at a known starting location
select gp_inject_fault_infinite('ftsLoop_before_probe', 'suspend', 1);
1&: select gp_request_fts_probe_scan();
select gp_wait_until_triggered_fault('ftsLoop_before_probe', 1, 1);

-- start multiple probes
2&: select gp_request_fts_probe_scan();
3&: select gp_request_fts_probe_scan();
-- ensure the probe requests start waiting before ftsLoop starts probe
select gp_wait_until_triggered_fault('ftsNotify_before', 3, 1);

-- finish the current ftsLoop iteration and pause before starting next iteration
select gp_inject_fault_infinite('ftsLoop_before_wait_latch', 'suspend', 1);
select gp_inject_fault('ftsLoop_before_probe', 'resume', 1);
-- all three requests should not be blocked by the next iteration
1<:
2<:
3<:

select gp_inject_fault('ftsLoop_before_probe', 'reset', 1);
select gp_inject_fault('ftsLoop_before_wait_latch', 'reset', 1);
select gp_inject_fault_infinite('ftsNotify_before', 'reset', 1);

-- reset the internal regular probe interval
!\retcode gpconfig -r gp_fts_probe_interval;
!\retcode gpstop -u;
