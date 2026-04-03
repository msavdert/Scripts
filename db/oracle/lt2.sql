--Session is displayed as <inst_id>.<sid>
with lk as (select blocking_instance||'.'||blocking_session blocker, inst_id||'.'||sid waiter 
            from gv$session where blocking_instance is not null and blocking_session is not null)
select lpad('  ',2*(level-1))||waiter lock_tree from
 (select * from lk
  union all
  select distinct 'root', blocker from lk
  where blocker not in (select waiter from lk))
connect by prior waiter=blocker start with blocker='root';

--Generate SQLs to kill top-level blockers [note3]
--To prevent killing wrong sessions, username:program is prefixed to the kill-session SQL for you to confirm
set serverout on
declare
  sess varchar2(20);
  sessinfo varchar2(29);
begin
  for i in 
    (with lk as (select blocking_instance||'.'||blocking_session blocker, inst_id||'.'||sid waiter
       from gv$session where blocking_instance is not null and blocking_session is not null)
     select distinct blocker from lk where blocker not in (select waiter from lk)
    )
  loop
    select regexp_substr(i.blocker,'[0-9]+$')||','||serial# ||',@' || regexp_substr(i.blocker,'[0-9]+'), 
      substr(username||':'||program,1,29) into sess, sessinfo
    from gv$session where inst_id = regexp_substr(i.blocker,'[0-9]+') and sid = regexp_substr(i.blocker,'[0-9]+$');
    dbms_output.put_line(sessinfo || ' ' || 'alter system kill session ''' || sess || ''' immediate;');
  end loop;
end;
/