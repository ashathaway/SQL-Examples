--Data request for small business team to report on BP inventory 

drop table if exists #policy_data;
drop table if exists #bp_cov_bldg;
drop table if exists #bp_cov_cl;
drop table if exists #bp_covg_term;
drop table if exists #premium;
drop table if exists #muli_st;
drop table if exists #exposure;
drop table if exists #exposure_sum;
drop table if exists #exposure_class;
drop table if exists #loss_ratio_1yr;
drop table if exists #temp1;
drop table if exists #temp2;
drop table if exists #loss_ratio_3yr;
drop table if exists Analytics.ash.data_bp_small_bus;


--------------------------------------------------
--starting grain with policy and building attributes
--------------------------------------------------
	select
		  ptp.policy_num_nk
		, pol.current_policy_num_nk
		, pol.current_account_num
		, pol.current_primary_insured_name
		, ptp.policy_exp_dt_nk
		, ptp.cob_nk
		, ptp.expiration_sic_code
		, bpc.loc_no_nk
		, bpc.bld_no_nk
		, bpc.state
		, ag.agent_name
		, agt_st.state_state_abbr as agency_state 
		, max(case when bpc.coverable_type = 'BPBldg' then bpc.coverable_keyword else null end) as bpbldg_coverable_keyword 
		, max(case when bpc.coverable_type = 'BPCl' then bpc.coverable_keyword else null end) as bpcl_coverable_keyword 
		, sum(prem.annual_premium) as sum_premium	
into #policy_data
	from UFGEDW.dbo.fact_premium prem
	left join UFGEDW.dbo.dim_policy pol
		on prem.policy_sk = pol.policy_sk
	-------------------------------------------
	left join UFGEDW.dbo.dim_policy_term_pit ptp
		on prem.policy_term_pit_sk = ptp.policy_term_pit_sk
	-------------------------------------------
	left join UFGEDW.dbo.dim_bp_coverable bpc
		on prem.bp_coverable_sk = bpc.bp_coverable_sk
	-------------------------------------------
	left join UFGEDW.dbo.dim_agent ag
		on prem.agent_sk = ag.agent_sk
	-------------------------------------------
	left join MISDB.dbo.state agt_st
		on ag.contract_state = agt_st.state_state_no
		and agt_st._source_deleted_datetime is null
	-------------------------------------------
	where bpc.policy_exp_dt_nk > GETDATE() --in force policies
		and ptp.policy_eff_dt <= GETDATE() --exclude future policies
		and ptp.source_system = 'GWPC' 
		and bpc.loc_no_nk is not null --need location info
		and bpc.bld_no_nk is not null --need building info
	group by 
		  ptp.policy_num_nk
		, pol.current_policy_num_nk
		, pol.current_account_num
		, pol.current_primary_insured_name
		, ptp.policy_exp_dt_nk
		, ptp.cob_nk
		, ptp.expiration_sic_code
		, bpc.loc_no_nk
		, bpc.bld_no_nk
		, bpc.state
		, ag.agent_name
		, agt_st.state_state_abbr --as agency_state 
	having sum(prem.annual_premium)>0



--------------------------------------------------
--BP coverage - building
--------------------------------------------------
select *
into #bp_cov_bldg
from 
(
	select
		  policy_num_nk
		, policy_exp_dt_nk
		, cob_nk
		, coverable_type
		, class_no_nk
		, coverable_keyword
		, row_exp_dts
		, end_exp_dt
		, loc_no_nk
		, bld_no_nk
		, address_line1
		, city
		, state
		, zip_code
		, county
		, square_footage
		, stories
		, year_built
		, roof_type_desc
		, construction_type_desc
		, auto_sprinkler
		, yr_roof_replaced
		, class_cd
		, class_desc
		, naics
		, sic
		, advt_pt_distance_to_coast
		, advt_pt_hail 
		, advt_pt_hurricane
		, advt_pt_stormi
		, ROW_NUMBER() over (partition by policy_num_nk, policy_exp_dt_nk, cob_nk, loc_no_nk, bld_no_nk order by row_exp_dts desc, end_exp_dt desc) as rn
	from UFGEDW.dbo.dim_bp_coverable bpc
	where 1=1
		and bpc.coverable_type = 'BPBldg' 
		and policy_exp_dt_nk >= GETDATE()
) a
where rn=1



--------------------------------------------------
--BP coverage - class
--------------------------------------------------
select *
into #bp_cov_cl
from 
(
	select
		  policy_num_nk
		, policy_exp_dt_nk
		, cob_nk
		, coverable_type
		, class_no_nk
		, coverable_keyword
		, row_exp_dts
		, end_exp_dt
		, loc_no_nk
		, bld_no_nk
		, address_line1
		, city
		, state
		, zip_code
		, county
		, square_footage
		, stories
		, year_built
		, roof_type_desc
		, construction_type_desc
		, auto_sprinkler
		, yr_roof_replaced
		, class_cd
		, class_desc
		, naics
		, sic
		, advt_pt_distance_to_coast
		, advt_pt_hail 
		, advt_pt_hurricane
		, advt_pt_stormi
		, ROW_NUMBER() over (partition by policy_num_nk, policy_exp_dt_nk, cob_nk, loc_no_nk, bld_no_nk, class_no_nk order by row_exp_dts desc, end_exp_dt desc) as rn
	from UFGEDW.dbo.dim_bp_coverable bpc
	where 1=1
		and bpc.coverable_type = 'BPCl' 
		and policy_exp_dt_nk >= GETDATE()
) a
where rn=1



--------------------------------------------------
--BP coverage term
--------------------------------------------------
select *
into #bp_covg_term
from
(
	select
		 policy_num_nk
		, policy_exp_dt_nk
		, cob_nk
		, coverable_keyword
		, coverable_type
		, row_exp_dts 
		, end_exp_dt
		, [Coverage | Building | Limit] as building_limit
		, [Coverage | Property Deductibles | Optional Deductible] as AOP_deductible 
		--, [Coverage | Business Personal Property | Business Personal Property Limit] as bus_personal_property_limit
		--, [Coverage | Windstorm Or Hail Percentage Deductibles] as wind_hail_deductibles
		, [Coverage | Property Deductibles | Windstorm or Hail Percentage Deductible] as wind_hail_deductibles
		, [Exclusion | Windstorm Or Hail Exclusion] as wind_hail_exclusion 
		, case when [PolicyCondition | Limitations On Coverage For Roof Surfacing | Indicate Applicability (Paragraph A. and/or Paragraph B.)] is not null then 1 else 0 end as limit_cov_roof_surfacing
		, ROW_NUMBER() over (partition by policy_num_nk, policy_exp_dt_nk, cob_nk, coverable_keyword order by row_exp_dts desc, end_exp_dt desc) as rn 
	from UFGEDW.dbo.dim_bp_covg_term
	where 1=1
		and coverable_type = 'BPBldg'
		and policy_exp_dt_nk >= GETDATE()
)a
where rn=1



--------------------------------------------------
--Premium per dec code
--------------------------------------------------
select
	  pol.current_policy_num_nk
	, ptp.policy_exp_dt_nk
	, sum(case when fp.dec_code_nk='BP' then fp.annual_premium end) as bp_sum_prem
	, sum(case when fp.dec_code_nk='WC' then fp.annual_premium end) as wc_sum_prem
	, sum(case when fp.dec_code_nk='CA' then fp.annual_premium end) as ca_sum_prem
	, sum(case when fp.dec_code_nk='CX' then fp.annual_premium end) as cx_sum_prem
into #premium
from UFGEDW.dbo.fact_premium fp
left join UFGEDW.dbo.dim_policy_term_pit ptp
	on fp.policy_term_pit_sk = ptp.policy_term_pit_sk
left join UFGEDW.dbo.dim_policy pol
	on fp.policy_sk = pol.policy_sk
group by pol.current_policy_num_nk
	, ptp.policy_exp_dt_nk



--------------------------------------------------
--Multiple state flag
--------------------------------------------------
select policy_num_nk
	, policy_exp_dt_nk
	, cob_nk
	, count(distinct state) as multiple_state_fl
into #muli_st
from #policy_data
group by policy_num_nk
	, policy_exp_dt_nk
	, cob_nk
having count(distinct state) > 1



--------------------------------------------------
--Exposure - payroll and sales
--------------------------------------------------
select 
    b.cob_nk
  , b.policy_num_nk
  , b.policy_exp_dt_nk
  , d.state_nk
  , c.loc_no_nk
  , c.bld_no_nk
  , c.class_no_nk
  , c.coverable_keyword
  , sum(a.annual_exposure) as annual_exposure
  , sum(a.annual_premium) as annual_premium
  , sum(case when exposure_basis_desc='Payroll' then a.annual_exposure else null end) as payroll_exposure
  , sum(case when exposure_basis_desc='Sales/Receipts' then a.annual_exposure else null end) as sales_exposure
  , sum(case when exposure_basis_desc='TIV' then a.annual_exposure else null end) as bpp_exposure
into #exposure
from UFGEDW.dbo.fact_premium a 
left join UFGEDW.dbo.dim_policy pol on a.policy_sk = pol.policy_sk
left join UFGEDW.dbo.dim_policy_lob b on a.policy_lob_sk = b.policy_lob_sk 
left join UFGEDW.dbo.dim_bp_coverable c on a.bp_coverable_sk = c.bp_coverable_sk
left join UFGEDW.dbo.dim_state_zip d on a.coverable_state_zip_sk = d.state_zip_sk
left join UFGEDW.dbo.dim_exposure_basis e on a.exposure_basis_sk = e.exposure_basis_sk
left join UFGEDW.dbo.dim_region g on a.region_sk = g.region_sk
left join UFGEDW.dbo.dim_policy_term_pit h on a.policy_term_pit_sk = h.policy_term_pit_sk
left join UFGEDW.dbo.dim_sysline i on a.sysline_sk = i.sysline_sk
----------------------------------------------------------------------------
where 1=1
	and a.dec_code_nk = 'BP'
	and i.sysline_nk in (5010, 5005) --BP liaiblity only in 5010, never in 5015
	and a.bp_coverable_sk > 0 --must have valid coverable
	and a.source_system = 'GWPC'
	and source_coverage_cd in
	( 'BP7ClassificationLiabMedExpensesBusnPrsnlProp-BPCl','BP7ClassificationBusnPrsnlProp-BPCl') 
group by
    b.cob_nk
  , b.policy_num_nk
  , b.policy_exp_dt_nk
  , d.state_nk
  , c.loc_no_nk
  , c.bld_no_nk
  , c.class_no_nk
  , c.coverable_keyword
having sum(annual_exposure) <> 0 or sum(annual_premium) <> 0



--------------------------------------------------
--Exposure per policy
--------------------------------------------------	
select 
	   cob_nk
	 , policy_num_nk
	 , policy_exp_dt_nk
	 , state_nk
	 , loc_no_nk
	 , bld_no_nk
	 , sum(payroll_exposure) payroll_exposure_sum
	 , sum(sales_exposure) sales_exposure_sum
	 , sum(bpp_exposure) bpp_exposure_sum
into #exposure_sum
from #exposure
group by cob_nk
	 , policy_num_nk
	 , policy_exp_dt_nk
	 , state_nk
	 , loc_no_nk
	 , bld_no_nk



--------------------------------------------------
--Class no based on exposure
--------------------------------------------------	
select *
into #exposure_class
from 
(
	select 
		   cob_nk
		 , policy_num_nk
		 , policy_exp_dt_nk
		 , state_nk
		 , loc_no_nk
		 , bld_no_nk
		 , class_no_nk
		 , coverable_keyword
		 , ROW_NUMBER() over (partition by cob_nk, policy_num_nk, policy_exp_dt_nk, loc_no_nk, bld_no_nk order by annual_premium desc, class_no_nk) as rn
	from #exposure
) a 
where rn=1



--------------------------------------------------
--Loss ratio - 1 yr
--------------------------------------------------	
select edw_pol.current_policy_num_nk
	, mis.expire_dt
	, sum(mis.earned_prem) earned
	, sum(mis.incurred) + sum(mis.ss) + sum(mis.expense) losses
into #loss_ratio_1yr
from (
	select prem.policy_num
		, prem.policy_pre
		, expire_dt
		, sum(prem_amt.earned_prem) earned_prem
		, 0 incurred
		, 0 ss
		, 0 expense
	
	from AnalyticsDB.mis.edw_premium prem
	
	left join AnalyticsDB.mis.edw_premium_amt prem_amt
		on prem.edw_premium_id = prem_amt.edw_premium_id
	
	where 1 = 1
		and prem.expire_dt >= GETDATE() 
		and prem.trancode < 80 --exclude taxes, surcharges, fees, etc.
		and prem.trancode not in (12, 17, 27, 37, 47, 57, 67) --no ceded or assumed
		and prem.percom_ind = 2 --only commercial lines
		and compy_br not between 800 and 999 --exclude broker insurance
		and prem._source_deleted_datetime is null
	
	group by prem.policy_num
		, prem.policy_pre
		, expire_dt
	
	having sum(prem_amt.earned_prem) <> 0
	
	union all
	
	select loss.policy_num
		, loss.policy_pre
		, comn1_cpolexp8n as expire_dt
		, 0 earned_prem
		, sum(case when trancode < 400 then loss.cl_amount * - 1 else 0 end) incurred
		, sum(case when trancode between 500 and 699 then loss.cl_amount else 0 end) ss
		, sum(case when trancode >= 700 then loss.cl_amount else 0 end) expense
	
	from AnalyticsDB.mis.edw_loss loss
	
	where 1 = 1
		and loss.comn1_cpolexp8n >= GETDATE()
		and dac_ind = 1 --only direct loss, no ceded or assumed
		and compy_br not between 800 and 999 --exclude broker insurance
		and percom_ind = 2 --only commercial lines
		and _source_deleted_datetime is null
	
	group by loss.policy_num
		, loss.policy_pre
		, comn1_cpolexp8n
	
	having sum(case when trancode < 400 then loss.cl_amount * - 1 else 0 end) <> 0
		or sum(case when trancode between 500 and 699 then loss.cl_amount else 0 end) <> 0
		or sum(case when trancode >= 700 then loss.cl_amount else 0 end) <> 0
	) mis
left join UFGEDW.dbo.dim_policy edw_pol
	on ltrim(rtrim(mis.policy_pre)) + mis.policy_num = edw_pol.policy_num_nk
group by edw_pol.current_policy_num_nk
	, mis.expire_dt



--------------------------------------------------
--Loss ratio - 3 yr --only if there are 3 yrs of policy terms else null
--------------------------------------------------
select edw_pol.current_policy_num_nk
	, mis.expire_dt
	, sum(mis.earned_prem) earned
	, sum(mis.incurred) + sum(mis.ss) + sum(mis.expense) losses
into #temp1
from (
	select prem.policy_num
		, prem.policy_pre
		, prem.expire_dt as expire_dt
		, sum(prem_amt.earned_prem) earned_prem
		, 0 incurred
		, 0 ss
		, 0 expense
	
	from AnalyticsDB.mis.edw_premium prem
	
	left join AnalyticsDB.mis.edw_premium_amt prem_amt
		on prem.edw_premium_id = prem_amt.edw_premium_id
	
	where 1 = 1
		and year(prem.expire_dt)>= year(getdate())-4 
		and prem.trancode < 80 --exclude taxes, surcharges, fees, etc.
		and prem.trancode not in (12, 17, 27, 37, 47, 57, 67) --no ceded or assumed
		and prem.percom_ind = 2 --only commercial lines
		and compy_br not between 800 and 999 --exclude broker insurance
	
	group by prem.policy_num
		, prem.policy_pre
		, prem.expire_dt
	
	having sum(prem_amt.earned_prem) <> 0
	
	union all
	
	select loss.policy_num
		, loss.policy_pre
		, loss.comn1_cpolexp8n as expire_dt
		, 0 earned_prem
		, sum(case when trancode < 400 then loss.cl_amount * - 1 else 0 end) incurred
		, sum(case when trancode between 500 and 699 then loss.cl_amount else 0 end) ss
		, sum(case when trancode >= 700 then loss.cl_amount else 0 end) expense
	
	from AnalyticsDB.mis.edw_loss loss
	
	where 1 = 1
		and year(loss.comn1_cpolexp8n)>= year(getdate())-4
		and dac_ind = 1 --only direct loss, no ceded or assumed
		and compy_br not between 800 and 999 --exclude broker insurance
		and percom_ind = 2 --only commercial lines
	
	group by loss.policy_num
		, loss.policy_pre
		, loss.comn1_cpolexp8n 
	
	having sum(case when trancode < 400 then loss.cl_amount * - 1 else 0 end) <> 0
		or sum(case when trancode between 500 and 699 then loss.cl_amount else 0 end) <> 0
		or sum(case when trancode >= 700 then loss.cl_amount else 0 end) <> 0
	) mis
------------------------------------
left join UFGEDW.dbo.dim_policy edw_pol
	on ltrim(rtrim(mis.policy_pre)) + mis.policy_num = edw_pol.policy_num_nk
group by edw_pol.current_policy_num_nk
	, mis.expire_dt
-------------------------------------------------------
select a.*
, b.min_expiration_yr
, case when year(expire_dt) - min_expiration_yr >= 2 then 1 else 0 end as three_yr_fl
into #temp2
from #temp1 a
left join 
( 
	select current_policy_num_nk, min(year(expire_dt)) as min_expiration_yr
	from #temp1 
	group by current_policy_num_nk
) b
	on a.current_policy_num_nk = b.current_policy_num_nk
-------------------------------------------------------
select a.current_policy_num_nk
	, a.expire_dt
	, sum(b.earned) earned
	, sum(b.losses) losses
into #loss_ratio_3yr
from #temp2 a
left join #temp1 b
	on a.current_policy_num_nk = b.current_policy_num_nk
	and year(b.expire_dt) between year(a.expire_dt) - 2 and year(a.expire_dt)
where a.three_yr_fl = 1
	and a.expire_dt >= GETDATE()
group by a.current_policy_num_nk, a.expire_dt



--------------------------------------------------
--join together temp tables
--------------------------------------------------
select 
	  a.policy_num_nk
	, a.current_account_num
	, a.current_primary_insured_name
	, a.policy_exp_dt_nk
	, a.cob_nk
	, a.loc_no_nk
	, a.bld_no_nk
	, bb.address_line1
	, bb.city
	, bb.state
	, case when st.multiple_state_fl>0 then 1 else 0 end as multiple_state_fl
	, SUBSTRING(bb.zip_code, 0, 6) as zip_code
	, bb.county
	, c.AOP_deductible 
	, c.building_limit
	, ex.bpp_exposure_sum as bus_personal_property_limit
	, c.wind_hail_deductibles
	, c.wind_hail_exclusion 
	, bc.square_footage
	, bb.stories
	, bb.year_built
	, bb.roof_type_desc
	, c.limit_cov_roof_surfacing
	, bb.construction_type_desc
	, bb.auto_sprinkler
	, bb.yr_roof_replaced
	, a.expiration_sic_code
	, bc.class_cd
	, bc.class_desc
	, bc.naics
	, bb.advt_pt_distance_to_coast
	, bb.advt_pt_hail 
	, bb.advt_pt_hurricane
	, bb.advt_pt_stormi
	, a.agent_name
	, a.agency_state
	, ex.payroll_exposure_sum
	, ex.sales_exposure_sum
	, case when lr_1yr.earned > 0 then lr_1yr.losses/lr_1yr.earned else null end as loss_ratio_1yr
	, case when lr_3yr.earned > 0 then lr_3yr.losses/lr_3yr.earned else null end as loss_ratio_3yr
	, p.bp_sum_prem
	, p.wc_sum_prem
	, p.ca_sum_prem
	, p.cx_sum_prem
into Analytics.ash.data_bp_small_bus
from #policy_data a
left join #bp_cov_bldg bb
	on a.policy_num_nk = bb.policy_num_nk
	and a.policy_exp_dt_nk = bb.policy_exp_dt_nk
	and a.cob_nk = bb.cob_nk
	and a.loc_no_nk = bb.loc_no_nk
	and a.bld_no_nk = bb.bld_no_nk
--------------------------------------------------
left join #exposure_class ex_c
	on a.policy_num_nk = ex_c.policy_num_nk
	and a.policy_exp_dt_nk = ex_c.policy_exp_dt_nk
	and a.cob_nk = ex_c.cob_nk
	and a.loc_no_nk = ex_c.loc_no_nk
	and a.bld_no_nk = ex_c.bld_no_nk
--------------------------------------------------
left join #bp_cov_cl bc
	on a.policy_num_nk = bc.policy_num_nk
	and a.policy_exp_dt_nk = bc.policy_exp_dt_nk
	and a.cob_nk = bc.cob_nk
	and a.loc_no_nk = bc.loc_no_nk
	and a.bld_no_nk = bc.bld_no_nk
	and ex_c.class_no_nk = bc.class_no_nk
--------------------------------------------------
left join #bp_covg_term c
	on a.policy_num_nk = c.policy_num_nk
	and a.policy_exp_dt_nk = c.policy_exp_dt_nk
	and a.cob_nk = c.cob_nk
	and bb.coverable_keyword =c.coverable_keyword
--------------------------------------------------
left join #premium p
	on a.current_policy_num_nk = p.current_policy_num_nk
	and a.policy_exp_dt_nk = p.policy_exp_dt_nk
--------------------------------------------------
left join #muli_st st
	on a.policy_num_nk = st.policy_num_nk
	and a.policy_exp_dt_nk = st.policy_exp_dt_nk
	and a.cob_nk = st.cob_nk
--------------------------------------------------
left join #exposure_sum ex
	on a.policy_num_nk = ex.policy_num_nk
	and a.policy_exp_dt_nk = ex.policy_exp_dt_nk
	and a.cob_nk = ex.cob_nk
	and a.loc_no_nk = ex.loc_no_nk
	and a.bld_no_nk = ex.bld_no_nk
	and bc.state = ex.state_nk
--------------------------------------------------
left join #loss_ratio_1yr lr_1yr
	on a.current_policy_num_nk = lr_1yr.current_policy_num_nk
	and a.policy_exp_dt_nk = lr_1yr.expire_dt
--------------------------------------------------
left join #loss_ratio_3yr lr_3yr
	on a.current_policy_num_nk = lr_3yr.current_policy_num_nk
	and a.policy_exp_dt_nk = lr_3yr.expire_dt