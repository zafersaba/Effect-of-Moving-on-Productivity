-- get only US locations for efficiency
create table location_us as 
select id,state from location 
where country="US" and state is not null;

-- get only the needed patent columns
create table patent_us as
select id,type,date from patent;

-- get the total citations of a patent 5 years after publishment
create view pc1 AS select c.patent_id as citer_id,c.citation_id as patent_id,c.date as patent_date, p.date as citation_date  from 
citation c inner join patent_us p on c.patent_id=p.id;

create table pc2 as select patent_id, count(*) as total_citations from pc1
where (JULIANDAY(citation_date)-JULIANDAY(patent_date))/365.25 < 5
group by patent_id
order by total_citations desc;

-- join patent and inventor tables to get the total citations of the patents of inventors
create table merged as
select pi.patent_id,pi.inventor_id,pi.location_id,p.date,l.state,pc.total_citations,p.type
from patent_inventor pi join patent_us p on pi.patent_id=p.id
join location_us l on pi.location_id=l.id
join pc2 pc on pi.patent_id=pc.patent_id;


-- add assignee_id to merged
create table merged2 as select m.*,a.assignee_id from merged m
inner join assignee_patent a on m.patent_id=a.patent_id;


-- remove duplicates. duplicate defined as having the same patent_id and inventor_id
create table merged3 as select * from merged2 where patent_id not in (SELECT patent_id from merged2
group by patent_id,inventor_id
having count(*)>1)
order by inventor_id,patent_id;


--mover identifying + year adding +filter year
create table merged4 as SELECT *, lag(state, 1) over (partition BY inventor_id ORDER BY date, patent_id) prev_state, 
lag(assignee_id, 1) over (partition BY inventor_id ORDER BY date, patent_id) prev_assignee_id,
lag(date, 1) over (partition BY inventor_id ORDER BY date, patent_id) prev_date,
strftime('%Y',date) as "year" 
FROM merged3
where year between '1996' and '2020'
order by inventor_id,patent_id;
;

--add 0 and 1 for moves. SMove=State change , FMove=Firm change
create table merged5 as
select *, CASE 
WHEN prev_state is not null and state<>prev_state and date<> prev_date then 1
ELSE 0
END as 'SMove',

CASE 
WHEN prev_assignee_id is not null and assignee_id!=prev_assignee_id and date<>prev_date then 1
ELSE 0
END as 'FMove'

from merged4
;

-- add time periods
create table merged6 as
select *,CASE 
WHEN year between '2006' and '2021' then 1
ELSE 0
END as 'MPeriod'
from merged5;

--Add SMover and FMover: People who move at the moving period. 
create table merged7 as
select *,CASE 
WHEN MPeriod=1 and SMove=1 then 1
ELSE 0
END as 'SMover',
CASE 
WHEN MPeriod=1 and FMove=1 then 1
ELSE 0
END as 'FMover'
from merged6;

--add interaction term
create table merged8 as
select *,SMover*FMover as 'smoverXfmover'
from merged7;

-- get the earliest patent date after moving
create table dam as select inventor_id, min(date) as date_after_move from merged8
where date>'2006' and (SMover=1 or FMover=1)
group by inventor_id;

-- get the latest patent date before moving 
create table dbm as 
select d.inventor_id, max(date) as date_before_move from merged8 m inner join dam d on m.inventor_id=d.inventor_id
where date<date_after_move
group by d.inventor_id;

-- merge patent dates and estimate the move date as the average of dam and dbm
create table movedates as 
select inventor_id,date_before_move,date_after_move,strftime("%Y-%m-%d",(julianday(date_after_move) + julianday(date_before_move))/2) as movedate
from 
(select * from dam left join dbm on dam.inventor_id=dbm.inventor_id
)
;

create table movedates2 as select *,  strftime('%Y',movedate) as move_year
from movedates;

-- create inventor tables
create table inventor2 as SELECT merged.inventor_id, MIN(date) as first_patent_date,inventor.male_flag as male
FROM merged inner join inventor on merged.inventor_id=inventor.id
GROUP BY inventor_id;

create table inventor3 as select i.*,max(m.SMover) as Smover, 
max(m.FMover) as FMover, max(m.smoverXfmover) as smoverXfmover 
from inventor2 i inner join merged8 m on i.inventor_id=m.inventor_id
group by m.inventor_id
;


--get year
create table inventor4 as
select inventor3.*, strftime('%Y',first_patent_date) as "first_patent_year" 
from inventor3;



create table temp as  select inventor_id,type, sum(total_citations) as citation_if
from merged2
group by inventor_id,type;

create table temp2 as 
select *,row_number() over (partition by inventor_id order by citation_if desc) as rn 
from temp 
order by inventor_id,type;


create table inventor_type as select inventor_id,type from temp2 where rn=1;

create table inventor5 as 
select m.inventor_id,m.year,sum(total_citations) as total_citations, first_patent_year,year - first_patent_year as experience,i.male,mo.move_year,
it.type,i.SMover,i.FMover,i.smoverXfmover, CASE
WHEN move_year is null then 0 
else year - move_year end 
as real_year

from  (merged8 m left join inventor4 i on m.inventor_id=i.inventor_id 
left join inventor_type it on i.inventor_id=it.inventor_id
left join movedates2 mo on i.inventor_id=mo.inventor_id)
group by m.inventor_id,year;



create table inventor6 as select *,year-1 as prev_year_1,year-2 as prev_year_2,year+1 as fwd_year_1,
year+2 as fwd_year_2,year+3 as fwd_year_3, year+4 as fwd_year_4, year+5 as fwd_year_5 from inventor5;
create table inventor6_copy as select inventor_id as inventoridb,year as yearb,total_citations as tcb from inventor6;

create table inventor7 as select a.*,b.tcb as prev_year_c from inventor6 a left join inventor6_copy b on a.inventor_id=b.inventoridb
and a.prev_year_1=yearb+1-1;



