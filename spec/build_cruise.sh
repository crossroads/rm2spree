PASS_FAIL=0

gem install dbd-odbc --version="0.2.5"
gem install dbi --version="0.4.5"
gem install activeresource --version="2.3.5"
cp config.yml.sample config_local.yml

spec --format progress --format html:$CC_BUILD_ARTIFACTS/rspec_report.html spec/
if [ "$?" -eq "1" ]; then
  PASS_FAIL=1
fi

# clean up builds older than 2 weeks ago so we don't run out of space
find -type d -name "build*" -mtime +14 -exec rm -rf \{} \;

exit $PASS_FAIL

