-- APEX Lazarus demo fault: ORA-00904 in the Employees report (page 2).
-- A deployment renames a column the region source selects. The same DDL runs
-- in both parsing schemas, as a scripted deployment would.

alter table lz_employees rename column email to email_address;
