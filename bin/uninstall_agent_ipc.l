LJ>@/tmp/eps_pkg.U13737/eps_agent/agent/bin/uninstall_agent_ipc.l�   G-   9   ' B   - &6 9 ' B6 9 BK  ��
closew	openio@/pathTransformfs UNINSTALL_FLAG_FILE currDir createFile 
file  �   ;&-   9   ' B   - &-  9 BK  ��remove@/pathTransformfs UNINSTALL_FLAG_FILE currDir deleteFile  � q2  X�6  -  ' &B- B-  . - -  X�- BX�6 -  ' &B- 9BK   �    	 exitLoop  send uninstall msg success	info send uninstall msg failed	warn




agentID DelUninstallFlag reTry MAX_RETRY_TIME sendUninstallAgent2Mgr ev res  err   � 	
 �--   9   B 6 '   ' &B- B-  9- -   ) 3 B-	 9B2  �K   �	����
�����startLoop 
send2  uninstall, send msg to mgragent:	infogetMyHostIdipc CreateUninstallFlag ustIpc dstIpc CMD_SEND_UNINSTALL_AGENT DelUninstallFlag reTry MAX_RETRY_TIME sendUninstallAgent2Mgr ev agentID  �   7� E6   ' B 6  ' B6  ' B6  ' B9' B) B)  ' )
 9 '	 +	 B  X�6
 '	 B6 9)	 B9 '	 9
 9 B  X�6
 '
 B6 9)
 B) 3	 3
 3  B2  �K     makeAddr mgr_ei failedFLAG_OFFLINELOC_MGRmgr_eimakeAddr	exitosnew ust_agent failed	warnust_agentnewuninstalling/var/log/edr_uninstallpathTransformlogfsevipcrequire	
#*BEEEEipc 4ev 1fs .reTry 	%UNINSTALL_FLAG_FILE $MAX_RETRY_TIME #ustIpc dstIpc CMD_SEND_UNINSTALL_AGENT 
CreateUninstallFlag DelUninstallFlag sendUninstallAgent2Mgr   