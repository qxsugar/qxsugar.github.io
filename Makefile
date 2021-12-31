.PHONY: commit
commit:
	git add . && git commit -m "site updated: `date '+%Y-%m-%d %H:%M:%S'`" && git push origin master