package DBIx::Class::Schema::Loader;

use strict;
use warnings;
use base qw/DBIx::Class::Schema/;
use base qw/Class::Data::Accessor/;
use Carp;
use UNIVERSAL::require;

# Always remember to do all digits for the version even if they're 0
# i.e. first release of 0.XX *must* be 0.XX000. This avoids fBSD ports
# brain damage and presumably various other packaging systems too
our $VERSION = '0.02999_03';

__PACKAGE__->mk_classaccessor('loader');

=head1 NAME

DBIx::Class::Schema::Loader - Dynamic definition of a DBIx::Class::Schema

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  sub _monikerize {
      my $name = shift;
      $name = join '', map ucfirst, split /[\W_]+/, lc $name;
      $name;
  }

  # __PACKAGE__->storage_type('::DBI'); # <- this is the default anyways
  __PACKAGE__->connection(
    "dbi:mysql:dbname",
    "root",
    "mypassword",
    { AutoCommit => 1 },
  );

  __PACKAGE__->load_from_connection(
    relationships           => 1,
    constraint              => '^foo.*',
    inflect_map             => { child => 'children' },
    moniker_map             => \&_monikerize,
    additional_classes      => [qw/DBIx::Class::Foo/],
    additional_base_classes => [qw/My::Stuff/],
    left_base_classes       => [qw/DBIx::Class::Bar/],
    components              => [qw/ResultSetManager/],
    resultset_components    => [qw/AlwaysRS/],
    debug                   => 1,
  );

  # in seperate application code ...

  use My::Schema;

  my $schema1 = My::Schema->connect( $dsn, $user, $password, $attrs);
  # -or-
  my $schema1 = "My::Schema";
  # ^^ defaults to dsn/user/pass from load_from_connection()

  # Get a list of the original (database) names of the tables that
  #  were loaded
  my @tables = $schema1->loader->tables;

  # Get a hashref of table_name => 'TableName' table-to-moniker
  #   mappings.
  my $monikers = $schema1->loader->monikers;

  # Get a hashref of table_name => 'My::Schema::TableName'
  #   table-to-classname mappings.
  my $classes = $schema1->loader->classes;

  # Use the schema as per normal for DBIx::Class::Schema
  my $rs = $schema1->resultset($monikers->{foo_table})->search(...);

=head1 DESCRIPTION

DBIx::Class::Schema::Loader automates the definition of a
DBIx::Class::Schema by scanning table schemas and setting up
columns and primary keys.

DBIx::Class::Schema::Loader supports MySQL, Postgres, SQLite and DB2.  See
L<DBIx::Class::Schema::Loader::Base> for more, and
L<DBIx::Class::Schema::Loader::Writing> for notes on writing your own
db-specific subclass for an unsupported db.

This module requires L<DBIx::Class> 0.05 or later, and obsoletes
L<DBIx::Class::Loader> for L<DBIx::Class> version 0.05 and later.

While on the whole, the bare table definitions are fairly straightforward,
relationship creation is somewhat heuristic, especially in the choosing
of relationship types, join types, and relationship names.  The relationships
generated by this module will probably never be as well-defined as
hand-generated ones.  Because of this, over time a complex project will
probably wish to migrate off of L<DBIx::Class::Schema::Loader>.

It is designed more to get you up and running quickly against an existing
database, or to be effective for simple situations, rather than to be what
you use in the long term for a complex database/project.

That being said, transitioning your code from a Schema generated by this
module to one that doesn't use this module should be straightforward and
painless, so don't shy away from it just for fears of the transition down
the road.

=head1 METHODS

=head2 load_from_connection

Example in Synopsis above demonstrates the available arguments.  For
detailed information on the arguments, see the
L<DBIx::Class::Schema::Loader::Base> documentation.

=cut

sub load_from_connection {
    my ( $class, %args ) = @_;

    # XXX this only works for relative storage_type, like ::DBI ...
    my $impl = "DBIx::Class::Schema::Loader" . $class->storage_type;

    $impl->require or
      croak qq/Could not load storage_type loader "$impl": / .
            qq/"$UNIVERSAL::require::ERROR"/;

    $args{schema} = $class;

    $class->loader($impl->new(%args));
    $class->loader->load;
}

=head2 loader

This is an accessor in the generated Schema class for accessing
the L<DBIx::Class::Schema::Loader::Base> -based loader object
that was used during construction.  See the
L<DBIx::Class::Schema::Loader::Base> docs for more information
on the available loader methods there.

=head1 KNOWN BUGS

Aside from relationship definitions being less than ideal in general,
this version is known not to handle the case of multiple relationships
between the same pair of tables.  All of the relationship code will
be overhauled on the way to 0.03, at which time that bug will be
addressed.

=head1 EXAMPLE

Using the example in L<DBIx::Class::Manual::ExampleSchema> as a basis
replace the DB::Main with the following code:

  package DB::Main;

  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->connection('dbi:SQLite:example.db');
  __PACKAGE__->load_from_connection(
      relationships => 1,
      debug         => 1,
  );

  1;

and remove the Main directory tree (optional).  Every thing else
should work the same

=head1 AUTHOR

Brandon Black, C<blblack@gmail.com>

Based on L<DBIx::Class::Loader> by Sebastian Riedel

Based upon the work of IKEBE Tomohiro

=head1 THANK YOU

Adam Anderson, Andy Grundman, Autrijus Tang, Dan Kubb, David Naughton,
Randal Schwartz, Simon Flack, Matt S Trout, everyone on #dbix-class, and
all the others who've helped.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

L<DBIx::Class>, L<DBIx::Class::Manual::ExampleSchema>

=cut

1;
