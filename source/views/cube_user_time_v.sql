CREATE OR REPLACE FORCE EDITIONABLE VIEW  "CUBE_USER_TIME_V" ("USERNAME", "CUBE_USER_ID", "CUBE_SIDE_ID", "SIDE", "PROJECT", "COLOR", "START_TIME", "END_TIME") AS 
  select cu.username, cu.cube_user_id, cs.cube_side_id, cs.side, cs.project, cs.color, ct.start_time, ct.end_time
    from cube_user cu
    inner join cube_side cs on cs.cube_user_id = cu.cube_user_id
    inner join cube_time ct on ct.cube_side_id = cs.cube_side_id
/