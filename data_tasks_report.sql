--Creating a dataset that combines two sources by unioning them together then creating a tableau report to view inventory 

drop table if exists Analytics.ash.data_tasks_gwpc_ir

select *
into Analytics.ash.data_tasks_gwpc_ir
from 
(
	SELECT  ac.AccountNumber as [KEY]
		  , ast.NAME as [action]
		  , NULL as [FileName]
		  , pp.PolicyNumber as [file_name] --file number
		  , NULL as FileTypeDescription
		  , case when actc.FirstName is not null then concat --only first letter of name is capitalized 
				(
					UPPER(SUBSTRING(actc.LastName, 1, 1)),
					LOWER(SUBSTRING(actc.LastName, 2, LEN(actc.LastName))),', ',
					UPPER(SUBSTRING(actc.FirstName, 1, 1)),
					LOWER(SUBSTRING(actc.FirstName, 2, LEN(actc.FirstName)))
				) 
			else NULL end as action_by_user
		  , a.CreateTime as available_date --when the task is first available to the user
		  , a.CloseDate as end_time  --when the step was finished
		  ,	case when assc.FirstName is not null then concat --only first letter of name is capitalized 
				(
					UPPER(SUBSTRING(assc.LastName, 1, 1)),
					LOWER(SUBSTRING(assc.LastName, 2, LEN(assc.LastName))),', ',
					UPPER(SUBSTRING(assc.FirstName, 1, 1)),
					LOWER(SUBSTRING(assc.FirstName, 2, LEN(assc.FirstName)))
				) 
			else NULL end as assigned_to
		  , NULL as send_to
		  , a.Subject as task_description
		  , NULL as flow
		  , ap.Subject as step
		  , a.ActivityPatternID as task_id
		  , 'PolicyCenter' as source_system
		  , NULL as operation_time_duration_sec
		  , ROW_NUMBER() OVER (PARTITION BY ac.AccountNumber, ap.Subject ORDER BY a.CloseDate desc) as rowNum --most recent action per account and step 
	FROM PolicyCenter.dbo.pc_activity as a
		LEFT JOIN  PolicyCenter.dbo.pc_account as ac
			on a.AccountID = ac.ID
		LEFT JOIN PolicyCenter.dbo.pctl_activitystatus as ast
			on a.Status = ast.PRIORITY
		LEFT JOIN PolicyCenter.dbo.pc_policyperiod as pp
			on a.PolicyID = pp.PolicyID
		LEFT JOIN PolicyCenter.dbo.pc_activitypattern as ap
			on a.ActivityPatternID = ap.ID
	--	action by user	--
		LEFT JOIN PolicyCenter.dbo.pc_user actu
			on a.UpdateUserID = actu.ID
		LEFT JOIN PolicyCenter.dbo.pc_contact actc
			on actu.ContactID = actc.ID
	--	assigned to user	--
		LEFT JOIN PolicyCenter.dbo.pc_user assu
			on a.AssignedByUserID = assu.ID
		LEFT JOIN PolicyCenter.dbo.pc_contact assc
			on assu.ContactID = assc.ID
	WHERE a.Subject NOT LIKE '%Document Metadata not received from ImageRight%' --from original IT gwpc query
		and a.CreateTime > DATEADD(YEAR, -1, GETDATE()) --filter to the last year of data for faster processing
) pc
where rowNum = 1
union all
select *
from
	(
	select *
	, ROW_NUMBER() OVER (PARTITION BY task_id, step ORDER BY end_time DESC) AS rowNum --last entered action from the task,step
	from
	(
		SELECT DISTINCT
			  HistoryId + SeqOrder as [KEY]
			, [Action] as [action]
			, [FileName]
			, FileNumber as [file_name] --file number
			, FileTypeDescription
			, ActionByUser as action_by_user
			, AvailableDate as available_date --when the task is first available to the user
			, EndTime as end_time --when the step was finished
			, AssignedTo as assigned_to
			, SendTo as send_to
			, TaskDescription as task_description
			, Flow as flow
			, Step as step
			, cast(TaskId as varchar) as task_id
			, SourceSystem as source_system
			, DATEDIFF(SECOND, LAG(EndTime,1,StartTime) OVER (PARTITION BY FileNumber ORDER BY EndTime), EndTime) AS operation_time_duration_sec
				--difference between the previous step's end time and the start time of the step assigned to the user
				--this is to show if there was a delay in the workflow etc. this will be either NULL or blank if it's the first step in the workflow/task
		 FROM 
			(
				SELECT DISTINCT 
						cast(th.historyid as varchar) AS HistoryId,
						cast(tha.seqorder as varchar) AS SeqOrder,
						tho.operationname AS [Action],
						f.filename AS [FileName],
						f.filenumber AS FileNumber,
						fd.description AS FileTypeDescription,
						em.LastName + ', ' + em.FirstName AS ActionByUser,
						th.dateavailable AS AvailableDate,
						tht.starttime AS StartTime,
						tha.operationtime AS EndTime,
						case when sa2.name=emp.Net_Login then concat(emp.LastName, ', ', emp.FirstName) else sa2.name end as AssignedTo,
						th.description AS TaskDescription,
						fd.flowname AS Flow,
						srd.stepname AS Step,
						th.taskid AS TaskId,
						thac.charvalue AS SendTo,
						'ImageRight' AS SourceSystem
				FROM
				ImageRight.dbo.TaskHistory AS th
				INNER JOIN ImageRight.dbo.TaskHistoryAction AS tha ON tha.historyid = th.historyid
				LEFT JOIN ImageRight.dbo.TaskHistoryAttrChar AS thac ON thac.historyid = th.historyid AND thac.attributeid = 2455
				LEFT JOIN ImageRight.dbo.Files AS f ON f.fileid = th.fileid
				INNER JOIN ImageRight.dbo.TaskHistoryOperation AS tho ON tho.operationid = tha.operationid
				LEFT JOIN ImageRight.dbo.SecurityAccount AS sa1 ON sa1.accountid = tha.accountid
				LEFT JOIN ImageRight.dbo.SecurityAccount AS sa2 ON sa2.accountid = th.assignedto
				INNER JOIN ImageRight.dbo.TaskHistoryTime AS tht ON tht.historytimeid = th.historytimeid
				INNER JOIN ImageRight.dbo.StepRootDef AS srd ON srd.steprootid = tht.steprootid
				INNER JOIN ImageRight.dbo.FlowDef AS fd ON fd.flowid = srd.flowid
				LEFT JOIN ImageRight.dbo.GroupMembers AS gm ON gm.accountid = tha.accountid
				LEFT JOIN dbUFG.dbo.Employee as em on em.Net_Login = sa1.name --added emplyoee table for action_by_user full name
				LEFT JOIN dbUFG.dbo.Employee as emp on emp.Net_Login = sa2.name --added emplyoee table for assigned_to full name 
				WHERE gm.groupid IN (2086, 2105, 2106, 2107, 2118, 2121, 2122, 2196, 2197,
										2224, 2225, 2315, 2326, 2327, 2329, 2338, 2339, 2245, 185776774,
										189078025, 193856409, 203571892, 206400258, 206400278,
										206400291, 206400317, 206400321, 206400348, 203571852,
										216930728, 203571835, 217803753) --given group ids from IT query 
					and th.dateavailable > DATEADD(YEAR, -1, GETDATE()) --filter to the last year of data for faster processing
					and th.dateavailable < DATEADD(YEAR, 1, GETDATE()) --exclude odd future data ie year 4787
				) as DISTINCTROWS
	) as DISTINCTROWS2
	where [Action] not in ('Lock', 'Unlock') --do not want to include these unimportant actions in the rownum
) as DISTINCTROWS3
where rowNum = 1