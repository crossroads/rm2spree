# Project variables
# -----------------------------------------------------
ruby_version=1.8.7
bundler_version=1.0.0

ruby_packages="ruby ruby-devel gcc rubygems"
cucumber_packages="libxml2 libxml2-devel libxslt libxslt-devel xorg-x11-server-Xvfb firefox ImageMagick"
required_packages="$ruby_packages $cucumber_packages"

# Install required pancakes, syrups, bacon, and cucumber extras.
# -----------------------------------------------------
yum --quiet -y install $required_packages

# Install RVM if not installed
# -----------------------------------------------------
if ! (which rvm) then
  bash < <( curl http://rvm.beginrescueend.com/releases/rvm-install-head )
fi

# Set up RVM as a function. This loads RVM into a shell session.
# -----------------------------------------------------
[[ -s "$HOME/.rvm/src/rvm/scripts/rvm" ]] && . "$HOME/.rvm/src/rvm/scripts/rvm"

# Install and use the configured ruby version
# -----------------------------------------------------
if ! (rvm list | grep $ruby_version); then rvm install $ruby_version; fi;
rvm use $ruby_version

if ! (gem list | grep "bundler"); then gem install bundler -v=$bundler_version --no-rdoc --no-ri; fi;


# Install Bundle
# -----------------------------------------------------
bundle install

# Core FFCRM Specs
# -----------------------------------------------------
RAILS_ENV=test rake bamboo:spec


