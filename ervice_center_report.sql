--Creating a new report for the 'Service Center' team that creates an inventory of their workload

--script unions the attributes together then sums the metrics into a table

--drop table if exists Analytics.ash.data_service_center_new
--drop table if exists #temp1

--create temp table of policies with the metrics from each table unioned together
select 
	  expiration_assigned_team
	, expiration_business_unit
	, master_agent_name
	, agent_name
	, agent_no
	, current_policy_num_nk
	, entry_month as entry_date
	, service_center_uw
	, current_uw
	, UPPER(LEFT(policy_new_renewal,1))+LOWER(SUBSTRING(policy_new_renewal,2,LEN(policy_new_renewal))) AS policy_new_renewal
	, dec_code
	, agent_contract_state
	, UPPER(LEFT(Region,1))+LOWER(SUBSTRING(Region,2,LEN(Region))) AS Region
	, adj_written_prem --use adj instead
	, incurred
	, SnS
	, expenses
	, adj_earned_prem
	, null as developed_retained_annual_premium
	, null as annual_premium
	, null as rate_premium_change
	, null as previous_premium_restated
	, null as inforce_prem
	, LastModifiedDateTime
into #temp1
from AnalyticsDB.tableau.data_profitability_by_sic 
where expiration_assigned_team='Service Center'
	and entry_month > '2019-01-01' --full year of historic data
---------------
union all
---------------
select 
	  expiration_assigned_team
	, expiration_business_unit
	, master_agent_name
	, agent_name
	, agent_no
	, current_policy_no
	, expiration_date as entry_date
	, service_center_uw
	, current_uw
	, null as policy_new_renewal
	, dec_code
	, agent_contract_state
	, UPPER(LEFT(Region,1))+LOWER(SUBSTRING(Region,2,LEN(Region))) AS Region
	, null as adj_written_prem
	, null as incurred
	, null as SnS
	, null as expenses
	, null as adj_earned_prem
	, developed_retained_annual_premium
	, annual_premium
	, null as rate_premium_change
	, null as previous_premium_restated
	, null as inforce_prem
	, LastModifiedDateTime
from AnalyticsDB.tableau.data_retention
where expiration_assigned_team='Service Center' --retention assign team instead??
	and region <> 'UFG SPECIALTY DIVISION'
	and expiration_date > '2019-01-01' --full year of historic data
---------------
union all
---------------
select
	  expiration_assigned_team
	, expiration_business_unit
	, master_agent_name
	, agent_name
	, agent_nk
	, current_policy_num_nk
	, booking_date as entry_date
	, service_center_uw
	, current_uw_name as current_uw
	, null as policy_new_renewal
	, dec_code_nk
	, agent_contract_state
	, UPPER(LEFT(region_group,1))+LOWER(SUBSTRING(region_group,2,LEN(region_group))) AS Region
	, null as adj_written_prem
	, null as incurred
	, null as SnS
	, null as expenses
	, null as adj_earned_prem
	, null as developed_retained_annual_premium
	, null as annual_premium
	, rate_premium_change
	, previous_premium_restated
	, null as inforce_prem
	, LastModifiedDateTime
from AnalyticsDB.tableau.vw_rate_vs_exposure_acctlvl
where expiration_assigned_team='Service Center'
	and outlier_flag = 'N'
	and region_group <> 'UFG SPECIALTY DIVISION'
	and booking_date > '2019-01-01' --full year of historic data
---------------
union all
---------------
select
	  expiration_assigned_team
	, expiration_business_unit
	, master_agent_name
	, agent_name
	, agent_no
	, policy_num_nk as current_policy_num_nk
	, policy_eff_dt as entry_date
	, service_center_uw
	, uw as current_uw
	, null as policy_new_renewal
	, dec_code_nk
	, agent_contract_state
	, UPPER(LEFT(region,1))+LOWER(SUBSTRING(region,2,LEN(region))) AS Region
	, null as adj_written_prem
	, null as incurred
	, null as SnS
	, null as expenses
	, null as adj_earned_prem
	, null as developed_retained_annual_premium
	, null as annual_premium
	, null as rate_premium_change
	, null as previous_premium_restated
	, inforce_prem
	, LastModifiedDateTime
from [AnalyticsDB].[tableau].[data_inforce_premium]
where expiration_assigned_team='Service Center'


--------------------------------
--sum the metrics into a table 
--------------------------------
select
	  a.expiration_assigned_team
	, a.expiration_business_unit
	, a.master_agent_name
	, a.agent_name
	, a.agent_no
	, b.tmfullname as territory_manager
	, a.current_policy_num_nk
	, a.entry_date
	, a.service_center_uw
	, a.current_uw
	, a.policy_new_renewal
	, a.dec_code
	, a.agent_contract_state
	, a.Region
	, a.LastModifiedDateTime
	, sum(a.adj_written_prem) as adj_written_prem_sum
	, sum(a.incurred) + sum(a.SnS) + sum(a.expenses) as losses
	, sum(a.adj_earned_prem) as adj_earned_prem_sum
	, sum(a.developed_retained_annual_premium) as developed_retained_annual_premium_sum
	, sum(a.annual_premium) as annual_premium_sum
	, sum(a.rate_premium_change) as rate_premium_change_sum
	, sum(a.previous_premium_restated) as previous_premium_restated_sum
	, sum(a.inforce_prem) as inforce_prem_sum
into Analytics.ash.data_service_center_new
from #temp1 a 
left join 
(
	SELECT 
			act.[ufg_agencynumber]
			, act.[name]
			, act.[statuscodename]
			, act.[ufg_futureterritory]
			, futterr.name AS future_territory_name
			, act.[ufg_futureterritoryeffectivedate]
			, act.[ufg_territoryeffectivedate]
			, ISNULL(terr.name, 'unknown') AS terrName
			, ISNULL(sys1user.firstname,'unknown') AS tmfirstname
			, ISNULL(sys1user.lastname,'unknown') AS tmlastname
			, ISNULL(sys1user.fullname,'unknown') AS tmfullname
			, ISNULL(sys1user.title,'unknown') AS tmtitle
	  FROM  Dynamics365.[download].account act
	  LEFT JOIN Dynamics365.download.[territory] terr ON act.territoryid = terr.territoryid
	  LEFT JOIN  Dynamics365.download.[systemuser] sys1user ON terr.managerid = sys1user.systemuserid
	  LEFT JOIN  Dynamics365.download.[territory] futterr ON act.ufg_futureterritory = futterr.territoryid
	  WHERE act.[ufg_agencynumber] IS NOT NULL
	  GROUP BY act.[ufg_agencynumber]
			, act.[name]
			, act.[statuscodename]
			, act.[ufg_futureterritory]
			, futterr.name 
			, act.[ufg_futureterritoryeffectivedate]
			, act.[ufg_territoryeffectivedate]
			, terr.name 
			, sys1user.firstname 
			, sys1user.lastname 
			, sys1user.fullname 
			, sys1user.title
) b
	on a.agent_no = b.ufg_agencynumber
group by
	  a.expiration_assigned_team
	, a.expiration_business_unit
	, a.master_agent_name
	, a.agent_name
	, a.agent_no
	, b.tmfullname
	, a.current_policy_num_nk
	, a.entry_date
	, a.service_center_uw
	, a.current_uw
	, a.policy_new_renewal
	, a.dec_code
	, a.agent_contract_state
	, a.Region
	, a.LastModifiedDateTime





---------------------------------------------------------------------------
--new to service center flag 

--at agency level
select 
	*
from
(
	select 
		*
		, ROW_NUMBER() over (partition by agent_no order by entry_month) as rn 
	from
	(
		SELECT
			agent_no,
			entry_month,
			expiration_assigned_team,
			CASE
				WHEN expiration_assigned_team = 'Service Center' AND previous_assigned_team <> 'Service Center' THEN 1
				ELSE 0
			END AS new_sc_fl
		FROM
		(
			SELECT
				agent_no,
				entry_month,
				expiration_assigned_team,
				LAG(expiration_assigned_team) OVER (PARTITION BY agent_no ORDER BY entry_month) AS previous_assigned_team
			FROM
				AnalyticsDB.tableau.data_profitability_by_sic
			where current_policy_num_nk ='10060454070'
			group by agent_no, entry_month, expiration_assigned_team
		) a 
	) b
	where new_sc_fl = 1
) c 
where rn = 1
order by entry_month


---------------------------------------------------------------------------------
--validation
--select 		  
--    current_policy_num_nk
--	, date_year
--	, dec_code
--	, count(*)
--from 
--(
--	select distinct 
--	  current_policy_num_nk
--	, entry_month
--	, dec_code
--	, policy_new_renewal
--	from AnalyticsDB.tableau.data_profitability_by_sic 
--	where expiration_assigned_team='Service Center'
--) a
--group by
--	  current_policy_num_nk
--	, entry_month
--	, dec_code
--having count(*)>1


--select 
--	  expiration_assigned_team
--	, master_agent_name
--	, master_agent_no
--	, agency_tier
--	, company
--	, current_policy_num_nk
--	, entry_month
--	, service_center_uw
--	, UPPER(LEFT(policy_new_renewal,1))+LOWER(SUBSTRING(policy_new_renewal,2,LEN(policy_new_renewal))) AS policy_new_renewal
--	, dec_code
--	, agent_contract_state
--	, UPPER(LEFT(Region,1))+LOWER(SUBSTRING(Region,2,LEN(Region))) AS Region
--	, written_prem
--	, incurred
--	, SnS
--	, expenses
--	, earned_prem
--from AnalyticsDB.tableau.data_profitability_by_sic 
--where current_policy_num_nk='60538468'
--and dec_code='CG'
--and  year(entry_month)='2024'