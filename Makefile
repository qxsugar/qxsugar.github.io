.PHONY: init
init:
	git submodule update --init --remote

.PHONY: deploy
deploy:
	hugo && cd public && git add . && git commit -m "site updated: `date '+%Y-%m-%d %H:%M:%S'`" && git push origin HEAD:master && cd ..

.PHONY: commit
commit:
	git add . && git commit -m "site updated: `date '+%Y-%m-%d %H:%M:%S'`" && git push origin master