package DBIx::Class::Schema::Loader;

use strict;
use warnings;
use base qw/DBIx::Class::Schema Class::Data::Accessor/;
use Carp::Clan qw/^DBIx::Class/;
use UNIVERSAL::require;
use Class::C3;
use Scalar::Util qw/ weaken /;

# Always remember to do all digits for the version even if they're 0
# i.e. first release of 0.XX *must* be 0.XX000. This avoids fBSD ports
# brain damage and presumably various other packaging systems too
our $VERSION = '0.04001';

__PACKAGE__->mk_classaccessor('_loader_args' => {});
__PACKAGE__->mk_classaccessors(qw/dump_to_dir _loader_invoked _loader/);

=head1 NAME

DBIx::Class::Schema::Loader - Dynamic definition of a DBIx::Class::Schema

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options(
      constraint              => '^foo.*',
      # debug                 => 1,
  );

  # in seperate application code ...

  use My::Schema;

  my $schema1 = My::Schema->connect( $dsn, $user, $password, $attrs);
  # -or-
  my $schema1 = "My::Schema"; $schema1->connection(as above);

=head1 DESCRIPTION 

DBIx::Class::Schema::Loader automates the definition of a
L<DBIx::Class::Schema> by scanning database table definitions and
setting up the columns, primary keys, and relationships.

DBIx::Class::Schema::Loader currently supports only the DBI storage type.
It has explicit support for L<DBD::Pg>, L<DBD::mysql>, L<DBD::DB2>,
L<DBD::SQLite>, and L<DBD::Oracle>.  Other DBI drivers may function to
a greater or lesser degree with this loader, depending on how much of the
DBI spec they implement, and how standard their implementation is.

Patches to make other DBDs work correctly welcome.

See L<DBIx::Class::Schema::Loader::DBI::Writing> for notes on writing
your own vendor-specific subclass for an unsupported DBD driver.

This module requires L<DBIx::Class> 0.07006 or later, and obsoletes
the older L<DBIx::Class::Loader>.

This module is designed more to get you up and running quickly against
an existing database, or to be effective for simple situations, rather
than to be what you use in the long term for a complex database/project.

That being said, transitioning your code from a Schema generated by this
module to one that doesn't use this module should be straightforward and
painless, so don't shy away from it just for fears of the transition down
the road.

=head1 METHODS

=head2 loader_options

Example in Synopsis above demonstrates a few common arguments.  For
detailed information on all of the arguments, most of which are
only useful in fairly complex scenarios, see the
L<DBIx::Class::Schema::Loader::Base> documentation.

If you intend to use C<loader_options>, you must call
C<loader_options> before any connection is made, or embed the
C<loader_options> in the connection information itself as shown
below.  Setting C<loader_options> after the connection has
already been made is useless.

=cut

sub loader_options {
    my $self = shift;
    
    my %args = (ref $_[0] eq 'HASH') ? %{$_[0]} : @_;
    $self->_loader_args(\%args);

    $self;
}

sub _invoke_loader {
    my $self = shift;
    my $class = ref $self || $self;

    my $args = $self->_loader_args;

    # set up the schema/schema_class arguments
    $args->{schema} = $self;
    $args->{schema_class} = $class;
    weaken($args->{schema}) if ref $self;
    $args->{dump_directory} ||= $self->dump_to_dir;

    # XXX this only works for relative storage_type, like ::DBI ...
    my $impl = "DBIx::Class::Schema::Loader" . $self->storage_type;
    $impl->require or
      croak qq/Could not load storage_type loader "$impl": / .
            qq/"$UNIVERSAL::require::ERROR"/;

    $self->_loader($impl->new(%$args));
    $self->_loader->load;
    $self->_loader_invoked(1);

    $self;
}

=head2 connection

See L<DBIx::Class::Schema> for basic usage.

If the final argument is a hashref, and it contains a key C<loader_options>,
that key will be deleted, and its value will be used for the loader options,
just as if set via the L</loader_options> method above.

The actual auto-loading operation (the heart of this module) will be invoked
as soon as the connection information is defined.

=cut

sub connection {
    my $self = shift;

    if($_[-1] && ref $_[-1] eq 'HASH') {
        if(my $loader_opts = delete $_[-1]->{loader_options}) {
            $self->loader_options($loader_opts);
            pop @_ if !keys %{$_[-1]};
        }
    }

    $self = $self->next::method(@_);

    my $class = ref $self || $self;
    if(!$class->_loader_invoked) {
        $self->_invoke_loader
    }

    return $self;
}

=head2 clone

See L<DBIx::Class::Schema>.

=cut

sub clone {
    my $self = shift;

    my $clone = $self->next::method(@_);

    if($clone->_loader_args) {
        $clone->_loader_args->{schema} = $clone;
        weaken($clone->_loader_args->{schema});
    }

    $clone;
}

=head2 dump_to_dir

Argument: directory name.

Calling this as a class method on either L<DBIx::Class::Schema::Loader>
or any derived schema class will cause all affected schemas to dump
manual versions of themselves to the named directory when they are
loaded.  In order to be effective, this must be set before defining a
connection on this schema class or any derived object (as the loading
happens as soon as both a connection and loader_options are set, and
only once per class).

See L<DBIx::Class::Schema::Loader::Base/dump_directory> for more
details on the dumping mechanism.

This can also be set at module import time via the import option
C<dump_to_dir:/foo/bar> to L<DBIx::Class::Schema::Loader>, where
C</foo/bar> is the target directory.

Examples:

    # My::Schema isa DBIx::Class::Schema::Loader, and has connection info
    #   hardcoded in the class itself:
    perl -MDBIx::Class::Schema::Loader=dump_to_dir:/foo/bar -MMy::Schema -e1

    # Same, but no hard-coded connection, so we must provide one:
    perl -MDBIx::Class::Schema::Loader=dump_to_dir:/foo/bar -MMy::Schema -e 'My::Schema->connection("dbi:Pg:dbname=foo", ...)'

    # Or as a class method, as long as you get it done *before* defining a
    #  connection on this schema class or any derived object:
    use My::Schema;
    My::Schema->dump_to_dir('/foo/bar');
    My::Schema->connection(........);

    # Or as a class method on the DBIx::Class::Schema::Loader itself, which affects all
    #   derived schemas
    use My::Schema;
    use My::OtherSchema;
    DBIx::Class::Schema::Loader->dump_to_dir('/foo/bar');
    My::Schema->connection(.......);
    My::OtherSchema->connection(.......);

    # Another alternative to the above:
    use DBIx::Class::Schema::Loader qw| dump_to_dir:/foo/bar |;
    use My::Schema;
    use My::OtherSchema;
    My::Schema->connection(.......);
    My::OtherSchema->connection(.......);

=cut

sub import {
    my $self = shift;
    return if !@_;
    foreach my $opt (@_) {
        if($opt =~ m{^dump_to_dir:(.*)$}) {
            $self->dump_to_dir($1)
        }
        elsif($opt eq 'make_schema_at') {
            no strict 'refs';
            my $cpkg = (caller)[0];
            *{"${cpkg}::make_schema_at"} = \&make_schema_at;
        }
    }
}

=head2 make_schema_at

This simple function allows one to create a Loader-based schema
in-memory on the fly without any on-disk class files of any
kind.  When used with the C<dump_directory> option, you can
use this to generate a rough draft manual schema from a dsn
without the intermediate step of creating a physical Loader-based
schema class.

The return value is the input class name.

This function can be exported/imported by the normal means, as
illustrated in these Examples:

    # Simple example, creates as a new class 'New::Schema::Name' in
    #  memory in the running perl interpreter.
    use DBIx::Class::Schema::Loader qw/ make_schema_at /;
    make_schema_at(
        'New::Schema::Name',
        { debug => 1 },
        [ 'dbi:Pg:dbname="foo"','postgres' ],
    );

    # Complex: dump loaded schema to disk, all from the commandline:
    perl -MDBIx::Class::Schema::Loader=make_schema_at,dump_to_dir:./lib -e 'make_schema_at("New::Schema::Name", { debug => 1 }, [ "dbi:Pg:dbname=foo","postgres" ])'

    # Same, but inside a script, and using a different way to specify the
    # dump directory:
    use DBIx::Class::Schema::Loader qw/ make_schema_at /;
    make_schema_at(
        'New::Schema::Name',
        { debug => 1, dump_directory => './lib' },
        [ 'dbi:Pg:dbname="foo"','postgres' ],
    );

=cut

sub make_schema_at {
    my ($target, $opts, $connect_info) = @_;

    {
        no strict 'refs';
        @{$target . '::ISA'} = qw/DBIx::Class::Schema::Loader/;
    }

    $target->loader_options($opts);
    $target->connection(@$connect_info);
}

=head2 rescan

Re-scans the database for newly added tables since the initial
load, and adds them to the schema at runtime, including relationships,
etc.  Does not process drops or changes.

Returns a list of the new monikers added.

=cut

sub rescan { my $self = shift; $self->_loader->rescan($self) }

=head1 EXAMPLE

Using the example in L<DBIx::Class::Manual::ExampleSchema> as a basis
replace the DB::Main with the following code:

  package DB::Main;

  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->loader_options(
      debug         => 1,
  );
  __PACKAGE__->connection('dbi:SQLite:example.db');

  1;

and remove the Main directory tree (optional).  Every thing else
should work the same

=head1 KNOWN ISSUES

=head2 Multiple Database Schemas

Currently the loader is limited to working within a single schema
(using the database vendors' definition of "schema").  If you
have a multi-schema database with inter-schema relationships (which
is easy to do in PostgreSQL or DB2 for instance), you only get to
automatically load the tables of one schema, and any relationships
to tables in other schemas will be silently ignored.

At some point in the future, an intelligent way around this might be
devised, probably by allowing the C<db_schema> option to be an
arrayref of schemas to load.

In "normal" L<DBIx::Class::Schema> usage, manually-defined
source classes and relationships have no problems crossing vendor schemas.

=head1 AUTHOR

Brandon Black, C<blblack@gmail.com>

Based on L<DBIx::Class::Loader> by Sebastian Riedel

Based upon the work of IKEBE Tomohiro

=head1 THANK YOU

Matt S Trout, all of the #dbix-class folks, and everyone who's ever sent
in a bug report or suggestion.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=head1 SEE ALSO

L<DBIx::Class>, L<DBIx::Class::Manual::ExampleSchema>

=cut

1;
