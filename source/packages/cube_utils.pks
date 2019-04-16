create or replace package cube_utils as

-- end the last entry and create a new one
procedure change_project(p_device_id  in varchar2,
                         p_side       in number);
                         

--
--  the function used by VPD to get the predicate for the tables
function get_predicate (
  d1    varchar2,
  d2    varchar2
  ) return varchar2;
  

--
--  the function to set the VPD security context based upon the user 
procedure set_vpd;      



end cube_utils;