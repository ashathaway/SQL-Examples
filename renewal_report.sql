--Report for managers to see renewal policies coming in 
--get attributes into temp tables to eventually combine together since they use different sources and level of detail
	
	
	DECLARE @databasename VARCHAR(100) = DB_NAME()
	DECLARE @schemaname VARCHAR(100) = OBJECT_SCHEMA_NAME(@@PROCID)
	DECLARE @procedurename VARCHAR(100) = OBJECT_NAME(@@PROCID)
	DECLARE @debugauditlogkey bigint = null

	DECLARE @STARTDATE datetime = NULL --CONVERT(VARCHAR(4), @year) + '-01-01 00:00:00.000'
	DECLARE @ENDDATE datetime = NULL

	SET @STARTDATE = '1900-01-01 00:00:00.000'
	SET @ENDDATE = GETDATE()

	DECLARE @end_date as date = getdate()

		----------------------------------------------------------------------
		--Account number in ACL using dim_policy_lob
		----------------------------------------------------------------------
		select policy_num_nk
			  ,account_num
			  ,source_system
			  ,rn
		into #act
		from
			(
				select policy_num_nk
						,account_num
						,source_system
						,ROW_NUMBER() over (partition by policy_num_nk order by policy_exp_dt_nk desc, end_eff_dt desc, row_eff_dts desc, cob_nk, dec_code_nk) as rn --most recent record
				from UFGEDW.dbo.dim_policy_lob
				where source_system = 'ACL'
				--and policy_exp_dt_nk > '2025-11-01'	--This is the cut-off date for ACL policies into PC. Since we are tracking conversions this has to be hardcoded for now.
			) a
		where rn = 1

		----------------------------------------------------------------------
		--Main rating state - i.e. state with highest premium
		----------------------------------------------------------------------
		select policy_num
			 , state_state_abbr as main_rating_state
		into #st
		from 
		(
			select policy_num
				 , state_state_abbr
				 , ROW_NUMBER() over (partition by policy_num order by sum_prem_per_st desc) as rn --choose state with highest premium as main state
			from
				(
					select policy_num
						 , state_state_abbr
						 , sum(adj_written_prem) as sum_prem_per_st
					from [AnalyticsDB].[tableau].[data_profitability_by_sic]
					group by policy_num
						, state_state_abbr
				) a
		) b
		where rn =  1

		----------------------------------------------------------------------
		--Sum of written premium per policy by state and expire dt
		----------------------------------------------------------------------
		select policy_num
			 , expire_dt
			 , state_state_abbr
			 , sum(adj_written_prem) as sum_adj_written_prem
		into #prem
		from [AnalyticsDB].[tableau].[data_profitability_by_sic] 
		--where expire_dt > '2025-11-01'
		group by policy_num
			   , expire_dt
			   , state_state_abbr

		----------------------------------------------------------------------
		--Status per policy
		----------------------------------------------------------------------
		select cob_nk
			 , policy_num_nk
			 , policy_exp_dt_nk
			 , max(case when policy_lob_status = 'ACTIVE' then 4
				   when policy_lob_status = 'PENDED' then 3
				   when policy_lob_status = 'LAPSED' then 2
				   when policy_lob_status = 'CANCELLED' then 1
				   end
				   ) as status_num
		into #polstat
			  from ufgedw.dbo.vw_policy_lob_status_current
			  group by cob_nk
					 , policy_num_nk
					 , policy_exp_dt_nk

		------------------------------------------------------------------------
		--1 policy yr loss ratio
		------------------------------------------------------------------------
		select current_policy_num_nk
			 , expire_dt
			 , sum(incurred) + sum(SnS) + sum(expenses) as losses_1yr
			 , sum(adj_earned_prem) as adj_earned_prem_1yr
		into #1yr
		from [AnalyticsDB].[tableau].[data_profitability_by_sic]
		where expire_dt >= @end_date
		group by current_policy_num_nk
			   , expire_dt

		------------------------------------------------------------------------
		--3 policy yr loss ratio
		------------------------------------------------------------------------
		--get the minimum expire dt from policy to confirm 3 years of history 
		select a.current_policy_num_nk
			 , a.expire_dt
			 , b.min_expiration_yr
			 , case when year(a.expire_dt) - b.min_expiration_yr >= 2 then 1 else 0 end as three_yr_fl
		into #temp1
		from 
		(
			select distinct current_policy_num_nk
						  , expire_dt
			from [AnalyticsDB].[tableau].[data_profitability_by_sic]
		) a
		left join 
		( 
			select current_policy_num_nk
				 , min(year(expire_dt)) as min_expiration_yr
			from  [AnalyticsDB].[tableau].[data_profitability_by_sic] 
			group by current_policy_num_nk
		) b
			on a.current_policy_num_nk = b.current_policy_num_nk
		-------------------------------------------------------
		--get 3 yr loss ratio if there is 3 yrs of policies
		select a.current_policy_num_nk
			 , a.expire_dt
			 , sum(b.incurred) + sum(b.SnS) + sum(b.expenses) as losses_3yr
			 , sum(b.adj_earned_prem) as adj_earned_prem_3yr
		into #3yr
		from #temp1 a
		left join [AnalyticsDB].[tableau].[data_profitability_by_sic] b
			on a.current_policy_num_nk = b.current_policy_num_nk
			and year(b.expire_dt) between year(a.expire_dt) - 2 and year(a.expire_dt)
		where a.three_yr_fl = 1
			and a.expire_dt >= @end_date
		group by 
			  a.current_policy_num_nk
			, a.expire_dt

		----------------------------------------------------------------------
		--Flag for each dec code 
		----------------------------------------------------------------------
		select policy_num
			 , expire_dt
			 , CP 
			 , PC 
			 , HO 
			 , BP 
			 , IM 
			 , FI 
			 , SU 
			 , CA 
			 , CG 
			 , OP 
			 , WC 
			 , CR 
			 , CX 
			 , CY 
			 , EO 
			 , OM
		into #pt
		from 
		(
			select policy_num
				 , expire_dt
				 , dec_code
				 , case when sum(adj_written_prem)<>0 then 1 else 0 end as sum_premium
			from [AnalyticsDB].[tableau].[data_profitability_by_sic] 
			group by policy_num
				   , expire_dt
				   , dec_code
		) as sourcetable
		PIVOT 
		(
			min(sum_premium) FOR dec_code IN
			(CP ,PC ,HO ,BP ,IM ,FI ,SU ,CA ,CG ,OP ,WC ,CR ,CX ,CY ,EO ,OM)
		) AS PivotTable

		----------------------------------------------------------------------
		--Umbrella limit 
		----------------------------------------------------------------------
		select policy_num_nk
			 , policy_exp_dt_nk
			 , cob_nk
			 , umbrella_limit
			 , rn
		into #umb
		from 
		(
		select 
			  policy_num_nk
			, policy_exp_dt_nk
			, cob_nk
			, umbrella_limit
			, ROW_NUMBER() over (partition by policy_num_nk, policy_exp_dt_nk, cob_nk, coverable_type, coverable_keyword order by end_eff_dt desc, row_eff_dts desc) as rn 
		from [UFGEDW].[dbo].[dim_cx_covg_term]
		) a
		where rn=1

		----------------------------------------------------------------------
		--Combine temp tables with profitability_by_sic data
		----------------------------------------------------------------------
		select trim(concat(pbs.policy_pre, pbs.policy_num)) as policy_num
			 , compy_br as cob
			 , pbs.effect_dt
			 , pbs.expire_dt
			 , pbs.insured_name
			 , act.account_num
			 , ptp.expiration_source_system
			 , pbs.agent_no
			 , pbs.agent_name
			 , pbs.current_uw
			 , case when ptp.retention_assigned_team = 'Underwriting Center' then 1 else 0 end as UWC_fl
			 , pbs.expiration_business_unit
			 , pbs.class_code_GL
			 , pbs.expiration_sic_code
			 , pbs.Region 
			 , pbs.state_state_abbr as exposure_state
			 , st.main_rating_state
			 , case when polstat.status_num = 4 then 'ACTIVE'
			 	when polstat.status_num = 3 then 'PENDED'
			 	when polstat.status_num = 2 then 'LAPSED'
			 	when polstat.status_num = 1 then 'CANCELLED'
			 	else 'UNKNOWN'
			 	end as policy_status
			 , u.umbrella_limit
			 , case when lr1.adj_earned_prem_1yr > 0 then lr1.losses_1yr / lr1.adj_earned_prem_1yr else null end as loss_ratio_1yr
			 , case when lr3.adj_earned_prem_3yr > 0 then lr3.losses_3yr / lr3.adj_earned_prem_3yr else null end as loss_ratio_3yr
			 , isnull(pt.CP, 0) as CP
			 , isnull(pt.PC, 0) as PC
			 , isnull(pt.HO, 0) as HO 
			 , isnull(pt.BP, 0) as BP 
			 , isnull(pt.IM, 0) as IM 
			 , isnull(pt.FI, 0) as FI 
			 , isnull(pt.SU, 0) as SU 
			 , isnull(pt.CA, 0) as CA 
			 , isnull(pt.CG, 0) as CG 
			 , isnull(pt.OP, 0) as OP 
			 , isnull(pt.WC, 0) as WC 
			 , isnull(pt.CR, 0) as CR 
			 , isnull(pt.CX, 0) as CX 
			 , isnull(pt.CY, 0) as CY 
			 , isnull(pt.EO, 0) as EO 
			 , isnull(pt.OM, 0) as OM
			 , prem.sum_adj_written_prem
		into #temp_final --[Analytics].[ash].[data_conversion_report] --drop table if exists #temp_final
		from [AnalyticsDB].[tableau].[data_profitability_by_sic] pbs
		inner join #act act --only acl policies
			on trim(concat(pbs.policy_pre, pbs.policy_num)) = act.policy_num_nk 
		left join #st st
			on pbs.policy_num = st.policy_num
		left join #prem prem 
			on pbs.policy_num = prem.policy_num and pbs.expire_dt = prem.expire_dt 
			and pbs.state_state_abbr = prem.state_state_abbr
		left join #polstat polstat
			on trim(concat(pbs.policy_pre, pbs.policy_num)) = polstat.policy_num_nk 
			and pbs.expire_dt = polstat.policy_exp_dt_nk
			and pbs.compy_br = polstat.cob_nk
		left join 
		(
			select policy_num_nk
				 , policy_exp_dt_nk
				 , cob_nk
				 , retention_assigned_team
				 , expiration_source_system
			from [UFGEDW].[dbo].[dim_policy_term_pit]
		) ptp
			on trim(concat(pbs.policy_pre, pbs.policy_num)) = ptp.policy_num_nk 
			and pbs.expire_dt = ptp.policy_exp_dt_nk
			and pbs.compy_br = ptp.cob_nk
		left join #1yr lr1
			on pbs.current_policy_num_nk = lr1.current_policy_num_nk 
			and pbs.expire_dt = lr1.expire_dt
		left join #3yr lr3
			on pbs.current_policy_num_nk = lr3.current_policy_num_nk 
			and pbs.expire_dt = lr3.expire_dt
		left join #pt pt
			on pbs.policy_num = pt.policy_num and pbs.expire_dt = pt.expire_dt
		left join #umb u
			on trim(concat(pbs.policy_pre, pbs.policy_num)) = u.policy_num_nk 
			and pbs.expire_dt = u.policy_exp_dt_nk
			and pbs.compy_br = u.cob_nk
			and pt.CX = 1 --only include limit when there is cx premium
		where pbs.expire_dt < DATEADD(year, 1, GETDATE()) --exlcude policies with future expire date over a year 
			 and polstat.status_num = 4 --only active policies
		group by
			  pbs.policy_num
			, pbs.policy_pre
			, compy_br --as cob
			, pbs.effect_dt
			, pbs.expire_dt
			, pbs.insured_name
			, act.account_num
			, ptp.expiration_source_system
			, pbs.agent_no
			, pbs.agent_name
			, pbs.current_uw
			, ptp.retention_assigned_team
			, pbs.expiration_business_unit
			, pbs.class_code_GL
			, pbs.expiration_sic_code
			, pbs.Region
			, pbs.state_state_abbr --as exposure_state
			, st.main_rating_state
			, polstat.status_num
			, u.umbrella_limit
			, lr1.losses_1yr
			, lr1.adj_earned_prem_1yr
			, lr3.losses_3yr
			, lr3.adj_earned_prem_3yr
			, prem.sum_adj_written_prem
	        , pt.CP
			, pt.PC
			, pt.HO
			, pt.BP
			, pt.IM
			, pt.FI
			, pt.SU
			, pt.CA
			, pt.CG
			, pt.OP
			, pt.WC
			, pt.CR
			, pt.CX
			, pt.CY
			, pt.EO
			, pt.OM