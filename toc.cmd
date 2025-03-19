	@echo off
	@REM call npm install -g markdown-toc
	
	@echo on
	call markdown-toc -i readme.md
		
	@echo on
	timeout /t 3 >nul
	@REM pause