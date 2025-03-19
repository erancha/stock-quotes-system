	@echo off
	@REM call npm install -g markdown-toc
	
	@echo on
	call markdown-toc -i solution.md
		
	@echo on
	timeout /t 3 >nul
	@REM pause