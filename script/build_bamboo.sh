# Project variables
# -----------------------------------------------------
application=rm2spree
ruby_version=ruby-1.8.7-p302
rubygems_version=1.3.7
bundler_version=1.0.9

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
. "/usr/local/rvm/scripts/rvm"

# Set up ruby environment
# -----------------------------------------------------
# Install and use the configured ruby version
if ! (rvm list | grep $ruby_version); then
    rvm install $ruby_version
fi
# Find/Create project gemset, and use it.
if ! (rvm list gemsets | grep "$ruby_version@$application "); then
    rvm use $ruby_version
    rvm gemset create "$application"
fi
rvm use "$ruby_version@$application"
# Install and use correct version of rubygems
if ! (gem -v | grep "$rubygems_version"); then
    # Only rubygems ~>1.6.2 can be downgraded.
    rvm rubygems 1.6.2
    if ! (gem -v | grep "$rubygems_version"); then
        gem update --system $rubygems_version
    fi
fi
# Install and use correct version of bundler.
if ! (gem list | grep "bundler" | grep $bundler_version); then
    gem install bundler -v=$bundler_version --no-rdoc --no-ri
fi

# Install Bundle
# -----------------------------------------------------
bundle install

# Run Specs
# -----------------------------------------------------
rake bamboo:spec

