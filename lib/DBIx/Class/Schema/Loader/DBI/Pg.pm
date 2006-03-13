package DBIx::Class::Schema::Loader::DBI::Pg;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Class::C3;

=head1 NAME

DBIx::Class::Schema::Loader::DBI::Pg - DBIx::Class::Schema::Loader Postgres Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE__->connection(
    dsn       => "dbi:Pg:dbname=dbname",
    user      => "postgres",
    password  => "",
  );

  __PACKAGE__->load_from_connection(
    relationships => 1,
  );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader>.

=head1 METHODS

=head2 load

Overlays L<DBIx::Class::Schema::Loader::Base>'s C<load()> to default the postgres
schema to C<public> rather than blank.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);
    $self->{db_schema} ||= 'public';
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my @uniqs;
    my $dbh = $self->schema->storage->dbh;

    my $sth = $dbh->prepare_cached(
        qq{SELECT conname,indexdef FROM pg_indexes JOIN pg_constraint }
      . qq{ON (pg_indexes.indexname = pg_constraint.conname) }
      . qq{WHERE schemaname=? and tablename=? and contype = 'u'}
    ,{}, 1);

    $sth->execute($self->db_schema, $table);
    while(my $constr = $sth->fetchrow_arrayref) {
        my $constr_name = $constr->[0];
        my $constr_def  = $constr->[1];
        my @cols;
        if($constr_def =~ /\(\s*([^)]+)\)\s*$/) {
            my $cols_text = $1;
            $cols_text =~ s/\s+$//;
            @cols = split(/\s*,\s*/, $cols_text);
            s/\Q$self->{_quoter}\E// for @cols;
        }
        if(!@cols) {
            warn "Failed to parse unique constraint $constr_name on $table";
        }
        else {
            push(@uniqs, { $constr_name => \@cols });
        }
    }

    return \@uniqs;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;