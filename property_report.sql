-----------------------------------------------------------------------
--BP and CP property data using pivot table format
-----------------------------------------------------------------------

	--drop all temporary tables that are selected into
	if object_id('tempdb..#working_table') is not null
		drop table #working_table
	if object_id('tempdb..#trancode_41_policies') is not null
		drop table #trancode_41_policies

	create table #working_table(
			 adj_entry_dt date NOT NULL
			, cob_nk varchar(25) NULL
			, dec_code_nk varchar(25) NULL
			, construction_type_desc varchar(255) NULL 
			, protection_class varchar(25) NULL
			, sprinkler_fl varchar(25) NULL
			, hurricane_risk varchar(25) NULL 
			, stormi_index varchar(25) NULL 
			, building_age varchar(25) NULL
			, expiration_business_unit varchar(255) NULL
			, expiration_industry_segment varchar(255) NULL
			, building_deductible INT NULL
			, wind_hail_deductible varchar(25) NULL 
			, Region varchar(255) NULL
			, betterview_risk_score INT NULL
			, measure varchar(100) NOT NULL
			, measure_value decimal(18,4) NOT NULL
	)


	--declare date variables
	DECLARE @getdate_minus_one as date = dateadd(day, -1, getdate()) --data always one day old, so minus one day
	DECLARE @start_date as date = DATEFROMPARTS(year(@getdate_minus_one)-2, 1, 1) --get beginning of 5 years ago --changed to two years
	DECLARE @end_date as date = EOMONTH(@getdate_minus_one) --end of current month

	--check timing of 41/51 trancodes
	--code taken from data_adjusted_written_premium
	select compy_br
			, policy_num_nk
			, expire_dt
			, dec_code
			, min(update_dt) min_update_dt
	into #trancode_41_policies
	from AnalyticsDB.mis.edw_premium
	where 1=1
		and trancode = 41
		and percom_ind = 2 --commercial only
		and _source_deleted_datetime is null
	group by compy_br
			, policy_num_nk
			, expire_dt
			, dec_code

		-----------------------------------
		----NEW POLICY COUNT------
		-----------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select 
			  adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(new_policy_count) AS policy_count
		from 
		(
			select 
				  adj_entry_dt
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
				, count(distinct policy_num_nk) as new_policy_count
			from 
			(
					select
					  bp.policy_num_nk
					, ptp.policy_eff_dt as adj_entry_dt
					, bp.cob_nk
					, fp.dec_code_nk
					, bp.bound_construction_type_desc as construction_type_desc
					, case when SUBSTRING(bp.bound_protection_class, 0, 2) > 7 then '8-10'
						when SUBSTRING(bp.bound_protection_class, 0, 2) > 3 then '4-7'
						when bp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
					, case when bp.bound_auto_sprinkler = 'Yes' then 'Y' 
						when bp.bound_auto_sprinkler = 'No' then 'N' 
						else null
						end as sprinkler_fl
					, h.hurricane_risk
					, s.stormi_index
					, case when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 50 then '>50 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 40 then '40-50 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 30 then '30-40 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 20 then '20-30 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 15 then '15-20 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 10 then '10-15 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 5 then '5-10 years'
						when bp.bound_year_built is null then 'NA'
						else '0-5 years'
						end as building_age
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, COALESCE(bpct.[bound_Coverage | Property Deductibles | Optional Deductible], bpct.bound_property_deductible) as building_deductible --acl or pc field 
					, COALESCE(bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible], bpct.bound_bdg_wind_hail_deductible) as wind_hail_deductible --acl or pc field 
					, r.region_group as Region
					, null as betterview_risk_score
					, 'new_policy_count' as measure
					, sum(
						case when lob.policy_lob_new_renewal = 'NEW BUSINESS'
							and fp.trans_eff_dt = ptp.policy_eff_dt
							and (
									(fp.trans_alloc_cd in ('NEW', 'RENEW', 'CANCEL'))
									or 
									(fp.trans_alloc_cd = 'REINSTATE' and fp.trans_proc_dts >= tc41.min_update_dt)
								)
						then fp.written_premium 
						else 0 end
						) 
					as written_premium
				from [UFGEDW].[dbo].[fact_premium] fp
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_lob lob
					on fp.policy_lob_sk = lob.policy_lob_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_region r
					on fp.region_sk = r.region_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_term_pit ptp
					on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_bp_coverable_pit bp
					on fp.bp_coverable_sk = bp.bp_coverable_sk
				--------------------------------------------------------
				left join [UFGEDW].[dbo].vw_dim_bp_covg_term_pit bpct
					on fp.bp_covg_term_sk = bpct.bp_covg_term_sk
				--------------------------------------------------------
				left join #trancode_41_policies tc41
					on ptp.cob_nk = tc41.compy_br
					and ptp.policy_num_nk = tc41.policy_num_nk
					and ptp.policy_exp_dt_nk = tc41.expire_dt
					and fp.dec_code_nk = tc41.dec_code
				--------------------------------------------------------
				left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
				--------------------------------------------------------
				left join [Analytics].[ash].[data_stormi_index] s
					on ptp.policy_num_nk = s.policy_num
				--------------------------------------------------------
				where 1=1
					and ptp.policy_eff_dt >= @start_date 
					and ptp.policy_eff_dt <= @end_date
					and fp.dec_code_nk='BP'
				group by 
					  bp.policy_num_nk
					, bp.policy_exp_dt_nk
					, bp.bound_loc_no_nk
					, bp.bound_bld_no_nk
					, ptp.policy_eff_dt
					, bp.cob_nk
					, fp.dec_code_nk
					, bp.bound_construction_type_desc 
					, bp.bound_protection_class
					, bp.bound_auto_sprinkler 
					, h.hurricane_risk 
					, s.stormi_index 
					, bp.bound_year_built
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, bpct.[bound_Coverage | Property Deductibles | Optional Deductible]
					, bpct.bound_property_deductible
					, bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible]
					, bpct.bound_bdg_wind_hail_deductible
					, r.region_group
			) a 
			where 1=1
				and written_premium > 0
				and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
			group by 
				 adj_entry_dt
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
		) a
		group by 
			adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		------------------------------------
		----NEW POLICY PREMIUM------
		-----------------------------------
		INSERT INTO #working_table
		(
			adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select
			  adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(written_premium) as new_policy_premium
		from 
		(
				select 
				  case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end as adj_entry_dt
				, bp.cob_nk
				, fp.dec_code_nk
				, bp.bound_construction_type_desc as construction_type_desc
				, case when SUBSTRING(bp.bound_protection_class, 0, 2) > 7 then '8-10'
						when SUBSTRING(bp.bound_protection_class, 0, 2) > 3 then '4-7'
						when bp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
				, case when bp.bound_auto_sprinkler = 'Yes' then 'Y' 
					when bp.bound_auto_sprinkler = 'No' then 'N' 
					else null
					end as sprinkler_fl
				, h.hurricane_risk
				, s.stormi_index
				, case when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 50 then '>50 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 40 then '40-50 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 30 then '30-40 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 20 then '20-30 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 15 then '15-20 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 10 then '10-15 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 5 then '5-10 years'
					when bp.bound_year_built is null then 'NA'
					else '0-5 years'
					end as building_age
				, ptp.expiration_business_unit
				, ptp.expiration_industry_segment
				, COALESCE(bpct.[bound_Coverage | Property Deductibles | Optional Deductible], bpct.bound_property_deductible) as building_deductible --acl or pc field 
				, COALESCE(bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible], bpct.bound_bdg_wind_hail_deductible) as wind_hail_deductible --acl or pc field 
				, r.region_group as Region
				, null as betterview_risk_score
				, 'new_policy_premium' as measure
				, sum(
						case when lob.policy_lob_new_renewal = 'NEW BUSINESS'
							and fp.trans_eff_dt = ptp.policy_eff_dt
							and (
									(fp.trans_alloc_cd in ('NEW', 'RENEW', 'CANCEL'))
									or 
									(fp.trans_alloc_cd = 'REINSTATE' and fp.trans_proc_dts >= tc41.min_update_dt)
								)
						then fp.written_premium 
						else 0 end
						) 
					as written_premium
			from  [UFGEDW].[dbo].[fact_premium] fp
			--------------------------------------------------------
			left join UFGEDW.dbo.dim_policy_lob lob
				on fp.policy_lob_sk = lob.policy_lob_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.dim_region r
				on fp.region_sk = r.region_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.dim_policy_term_pit ptp
				on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.vw_dim_bp_coverable_pit bp
				on fp.bp_coverable_sk = bp.bp_coverable_sk
			--------------------------------------------------------
			left join [UFGEDW].[dbo].vw_dim_bp_covg_term_pit bpct
				on fp.bp_covg_term_sk = bpct.bp_covg_term_sk
			--------------------------------------------------------
			left join #trancode_41_policies tc41
				on ptp.cob_nk = tc41.compy_br
				and ptp.policy_num_nk = tc41.policy_num_nk
				and ptp.policy_exp_dt_nk = tc41.expire_dt
				and fp.dec_code_nk = tc41.dec_code
			--------------------------------------------------------
			left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
			--------------------------------------------------------
			left join [Analytics].[ash].[data_stormi_index] s
				on ptp.policy_num_nk = s.policy_num
			--------------------------------------------------------
			where 1=1
				and case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end >= @start_date 
				and case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end <= @end_date
				and fp.dec_code_nk='BP'
			group by 
				 ptp.policy_eff_dt
				, fp.entry_dt
				, fp.trans_eff_dt
				, bp.cob_nk
				, fp.dec_code_nk
				, bp.bound_construction_type_desc 
				, bp.bound_protection_class
				, bp.bound_auto_sprinkler 
				, h.hurricane_risk 
				, s.stormi_index 
				, bp.bound_year_built
				, ptp.expiration_business_unit
				, ptp.expiration_industry_segment
				, bpct.[bound_Coverage | Property Deductibles | Optional Deductible]
				, bpct.bound_property_deductible
				, bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible]
				, bpct.bound_bdg_wind_hail_deductible
				, r.region_group
		) a 
		where 1=1
			and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		--------------------------------------
		------POLICY COUNT------
		-------------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(policy_count) AS policy_count
		from 
		(
			select 
				 adj_entry_dt
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
				, count(distinct policy_num_nk) as policy_count
			from 
			(
					select 
					  bp.policy_num_nk
					, ptp.policy_eff_dt as adj_entry_dt
					, bp.cob_nk
					, fp.dec_code_nk
					, bp.bound_construction_type_desc as construction_type_desc
					, case when SUBSTRING(bp.bound_protection_class, 0, 2) > 7 then '8-10'
						when SUBSTRING(bp.bound_protection_class, 0, 2) > 3 then '4-7'
						when bp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
					, case when bp.bound_auto_sprinkler = 'Yes' then 'Y' 
						when bp.bound_auto_sprinkler = 'No' then 'N' 
						else null
						end as sprinkler_fl
					, h.hurricane_risk
					, s.stormi_index
					, case when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 50 then '>50 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 40 then '40-50 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 30 then '30-40 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 20 then '20-30 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 15 then '15-20 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 10 then '10-15 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 5 then '5-10 years'
						when bp.bound_year_built is null then 'NA'
						else '0-5 years'
						end as building_age
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, COALESCE(bpct.[bound_Coverage | Property Deductibles | Optional Deductible], bpct.bound_property_deductible) as building_deductible --acl or pc field 
					, COALESCE(bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible], bpct.bound_bdg_wind_hail_deductible) as wind_hail_deductible --acl or pc field 
					, r.region_group as Region
					, null as betterview_risk_score
					, 'policy_count' as measure
					, sum(fp.written_premium) as written_premium
				from  [UFGEDW].[dbo].[fact_premium] fp
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_lob lob
					on fp.policy_lob_sk = lob.policy_lob_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_region r
					on fp.region_sk = r.region_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_term_pit ptp
					on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_bp_coverable_pit bp
					on fp.bp_coverable_sk = bp.bp_coverable_sk
				--------------------------------------------------------
				left join [UFGEDW].[dbo].vw_dim_bp_covg_term_pit bpct
					on fp.bp_covg_term_sk = bpct.bp_covg_term_sk
				--------------------------------------------------------
				left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
				--------------------------------------------------------
				left join [Analytics].[ash].[data_stormi_index] s
					on ptp.policy_num_nk = s.policy_num
				--------------------------------------------------------
				where 1=1
					and ptp.policy_eff_dt >= @start_date 
					and ptp.policy_eff_dt <= @end_date
					and fp.dec_code_nk='BP'
				group by 
					  bp.policy_num_nk
					, bp.policy_exp_dt_nk
					, bp.bound_loc_no_nk
					, bp.bound_bld_no_nk
					, ptp.policy_eff_dt
					, bp.cob_nk
					, fp.dec_code_nk
					, bp.bound_construction_type_desc 
					, bp.bound_protection_class
					, bp.bound_auto_sprinkler 
					, h.hurricane_risk 
					, s.stormi_index 
					, bp.bound_year_built
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, bpct.[bound_Coverage | Property Deductibles | Optional Deductible]
					, bpct.bound_property_deductible
					, bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible]
					, bpct.bound_bdg_wind_hail_deductible
					, r.region_group 
			) a 
			where 1=1
				and written_premium > 0
				and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
			group by 
				 adj_entry_dt
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
		) a
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		--------------------------------------
		------WRITTEN PREMIUM------
		-------------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(written_premium) as adj_written_prem
		from 
		(
				select 
				 case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end as adj_entry_dt
				, bp.cob_nk
				, fp.dec_code_nk
				, bp.bound_construction_type_desc as construction_type_desc
				, case when SUBSTRING(bp.bound_protection_class, 0, 2) > 7 then '8-10'
						when SUBSTRING(bp.bound_protection_class, 0, 2) > 3 then '4-7'
						when bp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
				, case when bp.bound_auto_sprinkler = 'Yes' then 'Y' 
					when bp.bound_auto_sprinkler = 'No' then 'N' 
					else null
					end as sprinkler_fl
				, h.hurricane_risk
				, s.stormi_index
				, case when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 50 then '>50 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 40 then '40-50 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 30 then '30-40 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 20 then '20-30 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 15 then '15-20 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 10 then '10-15 years'
					when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 5 then '5-10 years'
					when bp.bound_year_built is null then 'NA'
					else '0-5 years'
					end as building_age
				, ptp.expiration_business_unit
				, ptp.expiration_industry_segment
				, COALESCE(bpct.[bound_Coverage | Property Deductibles | Optional Deductible], bpct.bound_property_deductible) as building_deductible --acl or pc field 
				, COALESCE(bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible], bpct.bound_bdg_wind_hail_deductible) as wind_hail_deductible --acl or pc field 
				, r.region_group as Region
				, null as betterview_risk_score
				, 'adj_written_prem' as measure
				, sum(fp.written_premium) as written_premium
			from  [UFGEDW].[dbo].[fact_premium] fp
			--------------------------------------------------------
			left join UFGEDW.dbo.dim_policy_lob lob
				on fp.policy_lob_sk = lob.policy_lob_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.dim_region r
				on fp.region_sk = r.region_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.dim_policy_term_pit ptp
				on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.vw_dim_bp_coverable_pit bp
				on fp.bp_coverable_sk = bp.bp_coverable_sk
			--------------------------------------------------------
			left join [UFGEDW].[dbo].vw_dim_bp_covg_term_pit bpct
				on fp.bp_covg_term_sk = bpct.bp_covg_term_sk
			--------------------------------------------------------
			left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
			--------------------------------------------------------
			left join [Analytics].[ash].[data_stormi_index] s
				on ptp.policy_num_nk = s.policy_num
			--------------------------------------------------------
			where 1=1
				and case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end >= @start_date 
				and case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end <= @end_date
				and fp.dec_code_nk='BP'
			group by 
				  ptp.policy_eff_dt
				, fp.entry_dt
				, fp.trans_eff_dt
				, bp.bound_loc_no_nk
				, bp.bound_bld_no_nk
				, bp.cob_nk
				, fp.dec_code_nk
				, bp.bound_construction_type_desc 
				, bp.bound_protection_class
				, bp.bound_auto_sprinkler 
				, h.hurricane_risk 
				, s.stormi_index 
				, bp.bound_year_built
				, ptp.expiration_business_unit
				, ptp.expiration_industry_segment
				, bpct.[bound_Coverage | Property Deductibles | Optional Deductible]
				, bpct.bound_property_deductible
				, bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible]
				, bpct.bound_bdg_wind_hail_deductible
				, r.region_group
		) a 
		where 1=1
			and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		-----------------------------------
		----BUILDING COUNT------
		-----------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(building_count) AS building_count
		from 
		(
			select 
				  policy_num_nk
				, adj_entry_dt
				, policy_exp_dt_nk
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
				, COUNT(DISTINCT CONCAT(bound_loc_no_nk, '_', bound_bld_no_nk)) as building_count
			from 
			(
					select
					  bp.policy_num_nk
					, ptp.policy_eff_dt as adj_entry_dt
					, bp.policy_exp_dt_nk
					, bp.bound_loc_no_nk
					, bp.bound_bld_no_nk
					, bp.cob_nk
					, fp.dec_code_nk
					, bp.bound_construction_type_desc as construction_type_desc
					, case when SUBSTRING(bp.bound_protection_class, 0, 2) > 7 then '8-10'
						when SUBSTRING(bp.bound_protection_class, 0, 2) > 3 then '4-7'
						when bp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
					, case when bp.bound_auto_sprinkler = 'Yes' then 'Y' 
						when bp.bound_auto_sprinkler = 'No' then 'N' 
						else null
						end as sprinkler_fl
					, h.hurricane_risk
					, s.stormi_index
					, case when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 50 then '>50 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 40 then '40-50 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 30 then '30-40 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 20 then '20-30 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 15 then '15-20 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 10 then '10-15 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 5 then '5-10 years'
						when bp.bound_year_built is null then 'NA'
						else '0-5 years'
						end as building_age
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, COALESCE(bpct.[bound_Coverage | Property Deductibles | Optional Deductible], bpct.bound_property_deductible) as building_deductible --acl or pc field 
					, COALESCE(bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible], bpct.bound_bdg_wind_hail_deductible) as wind_hail_deductible --acl or pc field 
					, r.region_group as Region
					, null as betterview_risk_score
					, 'building_count' as measure
					, sum(fp.written_premium) as written_premium
				from [UFGEDW].[dbo].[fact_premium] fp
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_lob lob
					on fp.policy_lob_sk = lob.policy_lob_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_region r
					on fp.region_sk = r.region_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_term_pit ptp
					on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_bp_coverable_pit bp
					on fp.bp_coverable_sk = bp.bp_coverable_sk
				--------------------------------------------------------
				left join [UFGEDW].[dbo].vw_dim_bp_covg_term_pit bpct
					on fp.bp_covg_term_sk = bpct.bp_covg_term_sk
				--------------------------------------------------------
				left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
				--------------------------------------------------------
				left join [Analytics].[ash].[data_stormi_index] s
					on ptp.policy_num_nk = s.policy_num
				--------------------------------------------------------
				where 1=1
					and ptp.policy_eff_dt >= @start_date 
					and ptp.policy_eff_dt <= @end_date
					and fp.dec_code_nk='BP'
				group by 
					  bp.policy_num_nk
					, ptp.policy_eff_dt
					, bp.policy_exp_dt_nk
					, bp.bound_loc_no_nk
					, bp.bound_bld_no_nk
					, bp.cob_nk
					, fp.dec_code_nk
					, bp.bound_construction_type_desc 
					, bp.bound_protection_class
					, bp.bound_auto_sprinkler 
					, h.hurricane_risk 
					, s.stormi_index 
					, bp.bound_year_built
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, bpct.[bound_Coverage | Property Deductibles | Optional Deductible]
					, bpct.bound_property_deductible
					, bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible]
					, bpct.bound_bdg_wind_hail_deductible
					, r.region_group
			) a 
			where 1=1
				and written_premium > 0
				and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
			group by 
				  policy_num_nk
				, adj_entry_dt
				, policy_exp_dt_nk
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
		) a
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		-----------------------------------
		----NEW BUILDING COUNT------
		-----------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(building_count) AS building_count
		from 
		(
			select 
				  policy_num_nk
				, adj_entry_dt
				, policy_exp_dt_nk
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
				, COUNT(DISTINCT CONCAT(bound_loc_no_nk, '_', bound_bld_no_nk)) as building_count
			from 
			(
					select
					  bp.policy_num_nk
					, ptp.policy_eff_dt as adj_entry_dt
					, bp.policy_exp_dt_nk
					, bp.bound_loc_no_nk
					, bp.bound_bld_no_nk
					, bp.cob_nk
					, fp.dec_code_nk
					, bp.bound_construction_type_desc as construction_type_desc
					, case when SUBSTRING(bp.bound_protection_class, 0, 2) > 7 then '8-10'
						when SUBSTRING(bp.bound_protection_class, 0, 2) > 3 then '4-7'
						when bp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
					, case when bp.bound_auto_sprinkler = 'Yes' then 'Y' 
						when bp.bound_auto_sprinkler = 'No' then 'N' 
						else null
						end as sprinkler_fl
					, h.hurricane_risk
					, s.stormi_index
					, case when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 50 then '>50 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 40 then '40-50 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 30 then '30-40 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 20 then '20-30 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 15 then '15-20 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 10 then '10-15 years'
						when (YEAR(ptp.policy_eff_dt) - bp.bound_year_built) > 5 then '5-10 years'
						when bp.bound_year_built is null then 'NA'
						else '0-5 years'
						end as building_age
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, COALESCE(bpct.[bound_Coverage | Property Deductibles | Optional Deductible], bpct.bound_property_deductible) as building_deductible --acl or pc field 
					, COALESCE(bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible], bpct.bound_bdg_wind_hail_deductible) as wind_hail_deductible --acl or pc field 
					, r.region_group as Region
					, null as betterview_risk_score
					, 'new_building_count' as measure
					, sum(
						case when lob.policy_lob_new_renewal = 'NEW BUSINESS'
							and fp.trans_eff_dt = ptp.policy_eff_dt
							and (
									(fp.trans_alloc_cd in ('NEW', 'RENEW', 'CANCEL'))
									or 
									(fp.trans_alloc_cd = 'REINSTATE' and fp.trans_proc_dts >= tc41.min_update_dt)
								)
						then fp.written_premium 
						else 0 end
						) 
					as written_premium
				from [UFGEDW].[dbo].[fact_premium] fp
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_lob lob
					on fp.policy_lob_sk = lob.policy_lob_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_region r
					on fp.region_sk = r.region_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_term_pit ptp
					on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_bp_coverable_pit bp
					on fp.bp_coverable_sk = bp.bp_coverable_sk
				--------------------------------------------------------
				left join [UFGEDW].[dbo].vw_dim_bp_covg_term_pit bpct
					on fp.bp_covg_term_sk = bpct.bp_covg_term_sk
				--------------------------------------------------------
				left join #trancode_41_policies tc41
					on ptp.cob_nk = tc41.compy_br
					and ptp.policy_num_nk = tc41.policy_num_nk
					and ptp.policy_exp_dt_nk = tc41.expire_dt
					and fp.dec_code_nk = tc41.dec_code
				--------------------------------------------------------
				left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
				--------------------------------------------------------
				left join [Analytics].[ash].[data_stormi_index] s
					on ptp.policy_num_nk = s.policy_num
				--------------------------------------------------------
				where 1=1
					and ptp.policy_eff_dt >= @start_date 
					and ptp.policy_eff_dt <= @end_date
					and fp.dec_code_nk='BP'
				group by 
					  bp.policy_num_nk
					, ptp.policy_eff_dt
					, bp.policy_exp_dt_nk
					, bp.bound_loc_no_nk
					, bp.bound_bld_no_nk
					, bp.cob_nk
					, fp.dec_code_nk
					, bp.bound_construction_type_desc 
					, bp.bound_protection_class
					, bp.bound_auto_sprinkler 
					, h.hurricane_risk 
					, s.stormi_index 
					, bp.bound_year_built
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, bpct.[bound_Coverage | Property Deductibles | Optional Deductible]
					, bpct.bound_property_deductible
					, bpct.[bound_Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible]
					, bpct.bound_bdg_wind_hail_deductible
					, r.region_group
			) a 
			where 1=1
				and written_premium > 0
				and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
			group by 
				  policy_num_nk
				, adj_entry_dt
				, policy_exp_dt_nk
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
		) a
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure






------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
	--cp data
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

		-----------------------------------
		----NEW POLICY COUNT------
		-----------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(new_policy_count) AS policy_count
		from 
		(
			select 
				 adj_entry_dt
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
				, count(distinct policy_num_nk) as new_policy_count
			from 
			(
					select
					  cp.policy_num_nk
					, ptp.policy_eff_dt as adj_entry_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc as construction_type_desc
					, case when cp.bound_protection_class > 7 then '8-10'
						when cp.bound_protection_class > 3 then '4-7'
						when cp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
					, cp.bound_sprinkler_fl as sprinkler_fl
					, h.hurricane_risk
					, s.stormi_index
					, case when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 50 then '>50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 40 then '40-50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 30 then '30-40 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 20 then '20-30 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 15 then '15-20 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 10 then '10-15 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 5 then '5-10 years'
						when cp.bound_year_built is null then 'NA'
						else '0-5 years'
						end as building_age
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, cpct.bound_building_pd_deductible as building_deductible 
					, null as wind_hail_deductible 
					, r.region_group as Region
					, null as betterview_risk_score
					, 'new_policy_count' as measure
					, sum(
						case when lob.policy_lob_new_renewal = 'NEW BUSINESS'
							and fp.trans_eff_dt = ptp.policy_eff_dt
							and (
									(fp.trans_alloc_cd in ('NEW', 'RENEW', 'CANCEL'))
									or 
									(fp.trans_alloc_cd = 'REINSTATE' and fp.trans_proc_dts >= tc41.min_update_dt)
								)
						then fp.written_premium 
						else 0 end
						) 
					as written_premium
				from [UFGEDW].[dbo].[fact_premium] fp
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_lob lob
					on fp.policy_lob_sk = lob.policy_lob_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_region r
					on fp.region_sk = r.region_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_term_pit ptp
					on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_building_pit cp 
					on fp.cp_building_sk = cp.cp_building_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_covg_term_pit cpct
					on fp.cp_covg_term_sk = cpct.cp_covg_term_sk
				--------------------------------------------------------
				left join #trancode_41_policies tc41
					on ptp.cob_nk = tc41.compy_br
					and ptp.policy_num_nk = tc41.policy_num_nk
					and ptp.policy_exp_dt_nk = tc41.expire_dt
					and fp.dec_code_nk = tc41.dec_code
				--------------------------------------------------------
				left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
				--------------------------------------------------------
				left join [Analytics].[ash].[data_stormi_index] s
					on ptp.policy_num_nk = s.policy_num
				--------------------------------------------------------
				where 1=1
					and ptp.policy_eff_dt >= @start_date 
					and ptp.policy_eff_dt <= @end_date
					and fp.dec_code_nk='CP'
				group by 
					  cp.policy_num_nk
					, cp.policy_exp_dt_nk
					, cp.loc_no_nk
					, cp.bld_no_nk
					, ptp.policy_eff_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc 
					, cp.bound_protection_class
					, cp.bound_sprinkler_fl 
					, cp.bound_year_built
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, cpct.bound_building_pd_deductible
					, r.region_group
			) a 
			where 1=1
				and written_premium > 0
				and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
			group by 
				 adj_entry_dt
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
		) a
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		------------------------------------
		----NEW POLICY PREMIUM------
		-----------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			,SUM(written_premium) as new_policy_premium
		from 
		(
				select
					 case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end as adj_entry_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc as construction_type_desc
					, case when cp.bound_protection_class > 7 then '8-10'
						when cp.bound_protection_class > 3 then '4-7'
						when cp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
					, cp.bound_sprinkler_fl as sprinkler_fl
					, h.hurricane_risk
					, s.stormi_index
					, case when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 50 then '>50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 40 then '40-50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 30 then '30-40 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 20 then '20-30 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 15 then '15-20 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 10 then '10-15 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 5 then '5-10 years'
						when cp.bound_year_built is null then 'NA'
						else '0-5 years'
						end as building_age
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, bound_building_pd_deductible as building_deductible 
					, null as wind_hail_deductible 
					, r.region_group as Region
					, null as betterview_risk_score
					, 'new_policy_premium' as measure
					, sum(
						case when lob.policy_lob_new_renewal = 'NEW BUSINESS'
							and fp.trans_eff_dt = ptp.policy_eff_dt
							and (
									(fp.trans_alloc_cd in ('NEW', 'RENEW', 'CANCEL'))
									or 
									(fp.trans_alloc_cd = 'REINSTATE' and fp.trans_proc_dts >= tc41.min_update_dt)
								)
						then fp.written_premium 
						else 0 end) 
						as written_premium
				from [UFGEDW].[dbo].[fact_premium] fp
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_lob lob
					on fp.policy_lob_sk = lob.policy_lob_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_region r
					on fp.region_sk = r.region_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_term_pit ptp
					on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_building_pit cp 
					on fp.cp_building_sk = cp.cp_building_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_covg_term_pit cpct
					on fp.cp_covg_term_sk = cpct.cp_covg_term_sk
				--------------------------------------------------------
				left join #trancode_41_policies tc41
					on ptp.cob_nk = tc41.compy_br
					and ptp.policy_num_nk = tc41.policy_num_nk
					and ptp.policy_exp_dt_nk = tc41.expire_dt
					and fp.dec_code_nk = tc41.dec_code
				--------------------------------------------------------
				left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
				--------------------------------------------------------
				left join [Analytics].[ash].[data_stormi_index] s
					on ptp.policy_num_nk = s.policy_num
				--------------------------------------------------------
				where 1=1
					and case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end >= @start_date 
					and case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end <= @end_date
					and fp.dec_code_nk='CP'
				group by 
					  ptp.policy_eff_dt
					, fp.entry_dt
					, fp.trans_eff_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc 
					, cp.bound_protection_class
					, cp.bound_sprinkler_fl 
					, cp.bound_year_built
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, cpct.bound_building_pd_deductible
					, r.region_group
		) a 
		where 1=1
			and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		--------------------------------------
		------POLICY COUNT------
		-------------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(policy_count) AS policy_count
		from 
		(
			select 
				 adj_entry_dt
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
				, count(distinct policy_num_nk) as policy_count
			from 
			(
					select
					  cp.policy_num_nk
					, ptp.policy_eff_dt as adj_entry_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc as construction_type_desc
					, case when cp.bound_protection_class > 7 then '8-10'
						when cp.bound_protection_class > 3 then '4-7'
						when cp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
					, cp.bound_sprinkler_fl as sprinkler_fl
					, h.hurricane_risk
					, s.stormi_index
					, case when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 50 then '>50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 40 then '40-50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 30 then '30-40 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 20 then '20-30 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 15 then '15-20 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 10 then '10-15 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 5 then '5-10 years'
						when cp.bound_year_built is null then 'NA'
						else '0-5 years'
						end as building_age
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, bound_building_pd_deductible as building_deductible 
					, null as wind_hail_deductible 
					, r.region_group as Region
					, null as betterview_risk_score
					, 'policy_count' as measure
					, sum(fp.written_premium) as written_premium
				from [UFGEDW].[dbo].[fact_premium] fp
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_lob lob
					on fp.policy_lob_sk = lob.policy_lob_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_region r
					on fp.region_sk = r.region_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_term_pit ptp
					on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_building_pit cp 
					on fp.cp_building_sk = cp.cp_building_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_covg_term_pit cpct
					on fp.cp_covg_term_sk = cpct.cp_covg_term_sk
				--------------------------------------------------------
				left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
				--------------------------------------------------------
				left join [Analytics].[ash].[data_stormi_index] s
					on ptp.policy_num_nk = s.policy_num
				--------------------------------------------------------
				where 1=1
					and ptp.policy_eff_dt >= @start_date 
					and ptp.policy_eff_dt <= @end_date
					and fp.dec_code_nk='CP'
				group by 
					  cp.policy_num_nk
					, cp.policy_exp_dt_nk
					, cp.loc_no_nk
					, cp.bld_no_nk
					, ptp.policy_eff_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc 
					, cp.bound_protection_class
					, cp.bound_sprinkler_fl 
					, cp.bound_year_built
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, cpct.bound_building_pd_deductible
					, r.region_group
			) a 
			where 1=1
				and written_premium > 0
				and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
			group by 
				 adj_entry_dt
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
		) a
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		--------------------------------------
		------WRITTEN PREMIUM------
		-------------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(written_premium) as adj_written_prem
		from 
		(
			select
				 case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end as adj_entry_dt
				, cp.cob_nk
				, fp.dec_code_nk
				, cp.bound_construction_type_desc as construction_type_desc
				, case when cp.bound_protection_class > 7 then '8-10'
						when cp.bound_protection_class > 3 then '4-7'
						when cp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
				, cp.bound_sprinkler_fl as sprinkler_fl
				, h.hurricane_risk
				, s.stormi_index
				, case when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 50 then '>50 years'
					when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 40 then '40-50 years'
					when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 30 then '30-40 years'
					when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 20 then '20-30 years'
					when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 15 then '15-20 years'
					when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 10 then '10-15 years'
					when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 5 then '5-10 years'
					when cp.bound_year_built is null then 'NA'
					else '0-5 years'
					end as building_age
				, ptp.expiration_business_unit
				, ptp.expiration_industry_segment
				, bound_building_pd_deductible as building_deductible 
				, null as wind_hail_deductible 
				, r.region_group as Region
				, null as betterview_risk_score
				, 'adj_written_prem' as measure
				, sum(fp.written_premium) as written_premium
			from [UFGEDW].[dbo].[fact_premium] fp
			--------------------------------------------------------
			left join UFGEDW.dbo.dim_policy_lob lob
				on fp.policy_lob_sk = lob.policy_lob_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.dim_region r
				on fp.region_sk = r.region_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.dim_policy_term_pit ptp
				on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.vw_dim_cp_building_pit cp 
				on fp.cp_building_sk = cp.cp_building_sk
			--------------------------------------------------------
			left join UFGEDW.dbo.vw_dim_cp_covg_term_pit cpct
				on fp.cp_covg_term_sk = cpct.cp_covg_term_sk
			--------------------------------------------------------
			left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
			--------------------------------------------------------
			left join [Analytics].[ash].[data_stormi_index] s
				on ptp.policy_num_nk = s.policy_num
			--------------------------------------------------------
			where 1=1
				and case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end >= @start_date 
				and case when eomonth(fp.entry_dt) < fp.trans_eff_dt then fp.trans_eff_dt else fp.entry_dt end <= @end_date
				and fp.dec_code_nk='CP'
			group by 
				 ptp.policy_eff_dt
				, fp.entry_dt
				, fp.trans_eff_dt
				, cp.cob_nk
				, fp.dec_code_nk
				, cp.bound_construction_type_desc 
				, cp.bound_protection_class
				, cp.bound_sprinkler_fl 
				, cp.bound_year_built
				, ptp.expiration_business_unit
				, ptp.expiration_industry_segment
				, cpct.bound_building_pd_deductible
				, r.region_group
		) a 
		where 1=1
			and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		-----------------------------------
		----BUILDING COUNT------
		-----------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(building_count) AS building_count
		from 
		(
			select 
				  policy_num_nk
				, adj_entry_dt
				, policy_exp_dt_nk
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
				, COUNT(DISTINCT CONCAT(loc_no_nk, '_', bld_no_nk)) as building_count
			from 
			(
					select
					  cp.policy_num_nk
					, cp.policy_exp_dt_nk
					, cp.loc_no_nk
					, cp.bld_no_nk
					, ptp.policy_eff_dt as adj_entry_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc as construction_type_desc
					, case when cp.bound_protection_class > 7 then '8-10'
						when cp.bound_protection_class > 3 then '4-7'
						when cp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
					, cp.bound_sprinkler_fl as sprinkler_fl
					, h.hurricane_risk
					, s.stormi_index
					, case when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 50 then '>50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 40 then '40-50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 30 then '30-40 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 20 then '20-30 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 15 then '15-20 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 10 then '10-15 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 5 then '5-10 years'
						when cp.bound_year_built is null then 'NA'
						else '0-5 years'
						end as building_age
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, bound_building_pd_deductible as building_deductible 
					, null as wind_hail_deductible 
					, r.region_group as Region
					, null as betterview_risk_score
					, 'building_count' as measure
					, sum(fp.written_premium) as written_premium
				from [UFGEDW].[dbo].[fact_premium] fp
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_lob lob
					on fp.policy_lob_sk = lob.policy_lob_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_region r
					on fp.region_sk = r.region_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_term_pit ptp
					on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_building_pit cp 
					on fp.cp_building_sk = cp.cp_building_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_covg_term_pit cpct
					on fp.cp_covg_term_sk = cpct.cp_covg_term_sk
				--------------------------------------------------------
				left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
				--------------------------------------------------------
				left join [Analytics].[ash].[data_stormi_index] s
					on ptp.policy_num_nk = s.policy_num
				--------------------------------------------------------
				where 1=1
					and ptp.policy_eff_dt >= @start_date 
					and ptp.policy_eff_dt <= @end_date
					and fp.dec_code_nk='CP'
				group by 
					  cp.policy_num_nk
					, cp.policy_exp_dt_nk
					, cp.loc_no_nk
					, cp.bld_no_nk
					, ptp.policy_eff_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc 
					, cp.bound_protection_class
					, cp.bound_sprinkler_fl 
					, cp.bound_year_built
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, cpct.bound_building_pd_deductible
					, r.region_group
			) a 
			where 1=1
				and written_premium > 0
				and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
			group by 
				  policy_num_nk
				, adj_entry_dt
				, policy_exp_dt_nk
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
		) a
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure


		-----------------------------------
		----NEW BUILDING COUNT------
		-----------------------------------
		INSERT INTO #working_table
		(
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		)
		select 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, SUM(building_count) AS building_count
		from 
		(
			select 
				  policy_num_nk
				, adj_entry_dt
				, policy_exp_dt_nk
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
				, COUNT(DISTINCT CONCAT(loc_no_nk, '_', bld_no_nk)) as building_count
			from 
			(
					select
					  cp.policy_num_nk
					, cp.policy_exp_dt_nk
					, cp.loc_no_nk
					, cp.bld_no_nk
					, ptp.policy_eff_dt as adj_entry_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc as construction_type_desc
					, case when cp.bound_protection_class > 7 then '8-10'
						when cp.bound_protection_class > 3 then '4-7'
						when cp.bound_protection_class is null then 'NA'
						else '1-3'
						end as protection_class
					, cp.bound_sprinkler_fl as sprinkler_fl
					, h.hurricane_risk
					, s.stormi_index
					, case when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 50 then '>50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 40 then '40-50 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 30 then '30-40 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 20 then '20-30 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 15 then '15-20 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 10 then '10-15 years'
						when (YEAR(ptp.policy_eff_dt) - cp.bound_year_built) > 5 then '5-10 years'
						when cp.bound_year_built is null then 'NA'
						else '0-5 years'
						end as building_age
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, bound_building_pd_deductible as building_deductible 
					, null as wind_hail_deductible 
					, r.region_group as Region
					, null as betterview_risk_score
					, 'new_building_count' as measure
					, sum(
						case when lob.policy_lob_new_renewal = 'NEW BUSINESS'
							and fp.trans_eff_dt = ptp.policy_eff_dt
							and (
									(fp.trans_alloc_cd in ('NEW', 'RENEW', 'CANCEL'))
									or 
									(fp.trans_alloc_cd = 'REINSTATE' and fp.trans_proc_dts >= tc41.min_update_dt)
								)
						then fp.written_premium 
						else 0 end
						) 
					as written_premium
				from [UFGEDW].[dbo].[fact_premium] fp
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_lob lob
					on fp.policy_lob_sk = lob.policy_lob_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_region r
					on fp.region_sk = r.region_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.dim_policy_term_pit ptp
					on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_building_pit cp 
					on fp.cp_building_sk = cp.cp_building_sk
				--------------------------------------------------------
				left join UFGEDW.dbo.vw_dim_cp_covg_term_pit cpct
					on fp.cp_covg_term_sk = cpct.cp_covg_term_sk
				--------------------------------------------------------
				left join #trancode_41_policies tc41
					on ptp.cob_nk = tc41.compy_br
					and ptp.policy_num_nk = tc41.policy_num_nk
					and ptp.policy_exp_dt_nk = tc41.expire_dt
					and fp.dec_code_nk = tc41.dec_code
				-------------------------------------------------------
				left join [Analytics].[ash].[data_hurricane_risk] h
					on ptp.policy_num_nk = h.policy_num
				--------------------------------------------------------
				left join [Analytics].[ash].[data_stormi_index] s
					on ptp.policy_num_nk = s.policy_num
				--------------------------------------------------------
				where 1=1
					and ptp.policy_eff_dt >= @start_date 
					and ptp.policy_eff_dt <= @end_date
					and fp.dec_code_nk='CP'
				group by 
					  cp.policy_num_nk
					, cp.policy_exp_dt_nk
					, cp.loc_no_nk
					, cp.bld_no_nk
					, ptp.policy_eff_dt
					, cp.cob_nk
					, fp.dec_code_nk
					, cp.bound_construction_type_desc 
					, cp.bound_protection_class
					, cp.bound_sprinkler_fl 
					, cp.bound_year_built
					, ptp.expiration_business_unit
					, ptp.expiration_industry_segment
					, cpct.bound_building_pd_deductible
					, r.region_group
			) a 
			where 1=1
				and written_premium > 0
				and YEAR(a.adj_entry_dt) in ('2024','2025') --example data
			group by 
				  policy_num_nk
				, adj_entry_dt
				, policy_exp_dt_nk
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				, measure
		) a
		group by 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure



---------------------------------------------------------------------------
drop table if exists [Analytics].[ash].[data_gps_strategy];

		SELECT 
				 adj_entry_dt
				, cob_nk
				, dec_code_nk
				, construction_type_desc
				, protection_class
				, sprinkler_fl
				, hurricane_risk
				, stormi_index
				, building_age
				, expiration_business_unit
				, expiration_industry_segment
				, building_deductible
				, wind_hail_deductible
				, Region
				, betterview_risk_score
				,[new_policy_count]
				,[policy_count]
				,[new_policy_premium]
				,[adj_written_prem]
				,[building_count]
				,[new_building_count]
		--into #temp1
		into [Analytics].[ash].[data_gps_strategy]
		FROM 
		(
		  select 			 
			 adj_entry_dt
			, cob_nk
			, dec_code_nk
			, construction_type_desc
			, protection_class
			, sprinkler_fl
			, hurricane_risk
			, stormi_index
			, building_age
			, expiration_business_unit
			, expiration_industry_segment
			, building_deductible
			, wind_hail_deductible
			, Region
			, betterview_risk_score
			, measure
			, measure_value	
		  from #working_table a
		) as SourceTable
		PIVOT
		(	SUM([measure_value])
			FOR [Measure]
				IN (
					 [new_policy_count]
					,[policy_count]
					,[new_policy_premium]
					,[adj_written_prem]
					,[building_count]
					,[new_building_count]
				   )
			) as PT


--------------------------
--premium validation 
--------------------------
--get written prem from adj written prem to compare to my data premium

--select sum(adj_new_premium) as adj_new_premium
--from AnalyticsDB.tableau.data_adjusted_written_premium
--where 1=1 
--	and dec_code='CP'
--	--and DATEFROMPARTS(YEAR(adj_entry_dt),MONTH(adj_entry_dt),1) = '2025-06-01'
--	and YEAR(adj_entry_dt) = '2025'
--	and expiration_business_unit in ('Construction','Middle Market','Small Business')
------------------
--select sum(new_policy_premium) as edw_new_policy_premium
--from [Analytics].[ash].[data_gps_strategy]
--where 1=1
--	and dec_code_nk='CP'
--	--and DATEFROMPARTS(YEAR(adj_entry_dt),MONTH(adj_entry_dt),1) = '2025-06-01'
--	and YEAR(adj_entry_dt) = '2025'
--	and expiration_business_unit in ('Construction','Middle Market','Small Business')
------------------------------------------
--select sum(adj_written_premium) as adj_written_premium
--from AnalyticsDB.tableau.data_adjusted_written_premium
--where 1=1
--	and dec_code='CP'
--	--and DATEFROMPARTS(YEAR(adj_entry_dt),MONTH(adj_entry_dt),1) = '2025-06-01'
--	and YEAR(adj_entry_dt) = '2025'
--	and expiration_business_unit in ('Construction','Middle Market','Small Business')
-----------------
--select sum(adj_written_prem) as edw_adj_written_prem
--from [Analytics].[ash].[data_gps_strategy]
--where 1=1
--	and dec_code_nk='CP'
--	--and DATEFROMPARTS(YEAR(adj_entry_dt),MONTH(adj_entry_dt),1) = '2025-06-01'
--	and YEAR(adj_entry_dt) = '2025'
--	and expiration_business_unit in ('Construction','Middle Market','Small Business')



--------------------------
--policy count validation 
--------------------------
--get policy counts from adj written prem to compare to my data counts
--
--select count(distinct policy_num_nk) as adj_policy_count
--from AnalyticsDB.tableau.data_adjusted_written_premium
--where 1=1 
--	and dec_code='BP'
--	--and DATEFROMPARTS(YEAR(adj_entry_dt),MONTH(adj_entry_dt),1) = '2025-06-01'
--	and YEAR(adj_entry_dt) = '2025'
--	and expiration_business_unit in ('Construction','Middle Market','Small Business')
----------------
--select sum(policy_count) as policy_count
--from [AnalyticsDB].[tableau].[data_executive_production]
--where year(entry_mo)='2025'
--	and reporting_segment_lob='BP'
------------------
--select sum(policy_count) as edw_policy_count
--from [Analytics].[ash].[data_gps_strategy]
--where 1=1
--	and dec_code_nk='BP'
--	--and DATEFROMPARTS(YEAR(adj_entry_dt),MONTH(adj_entry_dt),1) = '2025-06-01'
--	and YEAR(adj_entry_dt) = '2025'
--	and expiration_business_unit in ('Construction','Middle Market','Small Business')
----------------------------------------
--select count(distinct policy_num_nk) as adj_new_policy_count
--from AnalyticsDB.tableau.data_adjusted_written_premium
--where 1=1
--	and dec_code='BP'
--	--and DATEFROMPARTS(YEAR(adj_entry_dt),MONTH(adj_entry_dt),1) = '2025-06-01'
--	and YEAR(adj_entry_dt) = '2025'
--	and expiration_business_unit in ('Construction','Middle Market','Small Business')
--	and policy_lob_new_renewal='NEW BUSINESS'
---------------
--select sum(new_policy_count) as new_policy_count
--from [AnalyticsDB].[tableau].[data_executive_production]
--where year(entry_mo)='2025'
--	and reporting_segment_lob='BP'
-----------------
--select sum(new_policy_count) as edw_new_policy_count
--from [Analytics].[ash].[data_gps_strategy]
--where 1=1
--	and dec_code_nk='BP'
--	--and DATEFROMPARTS(YEAR(adj_entry_dt),MONTH(adj_entry_dt),1) = '2025-06-01'
--	and YEAR(adj_entry_dt) = '2025'
--	and expiration_business_unit in ('Construction','Middle Market','Small Business')