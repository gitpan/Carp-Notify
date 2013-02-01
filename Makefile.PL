
use strict;
use warnings;

use 5.005;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Loudly complain in lots of places when things break badly",
  "AUTHOR" => "Brian Conry <perl\@theconrys.com>, Jim Thomason <thomasoniii\@yahoo.com>",
  "BUILD_REQUIRES" => {
    "Test::More" => 0,
    "vars" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Carp-Notify",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Carp::Notify",
  "PREREQ_PM" => {
    "strict" => 0
  },
  "VERSION" => "1.11",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



