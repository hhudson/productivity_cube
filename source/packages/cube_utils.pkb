create or replace package body cube_utils as

-- end the last entry and create a new one
procedure change_project(p_device_id  in varchar2,
                         p_side       in number) as

l_user      varchar2(256);
l_cu_id     number;
l_cs_id     number;
l_project   varchar2(2000);
l_now       date := sysdate; -- get a consistent date to use to end current and start next
l_last_time date;
l_last_side number;

begin

  -- get info about the cube
  select cu.username, cu.cube_user_id, cs.cube_side_id
    into l_user, l_cu_id, l_cs_id
    from cube_user cu
    inner join cube_side cs on cs.cube_user_id = cu.cube_user_id -- yep, that's the way I roll
    where cu.cube_device_id = p_device_id
      and cs.side = p_side;
      
  begin
  
    select ct.start_time , cs.side
      into l_last_time, l_last_side
      from cube_time ct
      inner join cube_side cs on cs.cube_side_id = ct.cube_side_id
      where ct.end_time is null
        and ct.cube_user_id = l_cu_id;
        
  exception 
     when no_data_found then  -- this is the first time the cube is used
       l_last_time := sysdate - 1;
       l_last_side := null;
  end;
    
  if (l_last_side is null) or (l_last_side != p_side) then  -- only record if there has been a change
    
    -- end the time on the last record  
    update cube_time
      set end_time = l_now
      where cube_user_id = l_cu_id
        and end_time is null;
  
    -- put in the project we are currenlty working on
    insert into cube_time (cube_user_id, cube_side_id, start_time )
      values (l_cu_id, l_cs_id, l_now);
  end if;

end change_project;


--
-- see pkg spec
function get_predicate (
  d1    varchar2,
  d2    varchar2
  ) return varchar2 is

begin

  return q'! CUBE_USER_ID = sys_context ('CUBE_SECURITY_CONTEXT','userid') !';

end get_predicate;


--
-- see pkg spec
procedure set_vpd as

begin

  -- get the logged in user
  
  -- get the user id
  
  -- set the context
  null;
end;

end cube_utils;