PASS_FAIL=0
cp config.yml.sample config_local.yml
spec --format progress --format html:$CC_BUILD_ARTIFACTS/rspec_report.html spec/
if [ "$?" -eq "1" ]; then
  PASS_FAIL=1
fi
exit $PASS_FAIL
