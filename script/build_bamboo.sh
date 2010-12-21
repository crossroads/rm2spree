# Project variables
# -----------------------------------------------------
project_name=rm2spree
ruby_version=1.8.7

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

# Set up and use project gemset for ruby version
rvm use $ruby_version
rvm gemset create $project_name
rvm use $ruby_version@$project_name

# Install Bundle
# -----------------------------------------------------
bundle install

# Run Specs
# -----------------------------------------------------
rake bamboo:spec

