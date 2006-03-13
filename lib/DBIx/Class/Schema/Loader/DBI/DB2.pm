package DBIx::Class::Schema::Loader::DBI::DB2;

use strict;
use warnings;
use base 'DBIx::Class::Schema::Loader::DBI';
use Class::C3;

=head1 NAME

DBIx::Class::Schema::Loader::DBI::DB2 - DBIx::Class::Schema::Loader DB2 Implementation.

=head1 SYNOPSIS

  package My::Schema;
  use base qw/DBIx::Class::Schema::Loader/;

  __PACKAGE_->connection(
    dsn         => "dbi:DB2:dbname",
    user        => "myuser",
    password    => "",
  );

  __PACKAGE__->load_from_connection(
    relationships => 1,
    db_schema     => "MYSCHEMA",
  );

  1;

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader::Base>.

=cut

sub _setup {
    my $self = shift;

    $self->next::method(@_);
    $self->{_column_info_broken} = 1;
}

# DB2 wants the table name in uppercase, but
#   otherwise the standard methods work for these
#   two methods
sub _table_pk_info {
    my ( $self, $table ) = @_;
    $self->next::method(uc $table);
}

sub _table_fk_info {
    my ($self, $table) = @_;
    $self->next::method(uc $table);
}

sub _table_uniq_info {
    my ($self, $table) = @_;

    my @uniqs;

    my $dbh = $self->schema->storage->dbh;

    my $sth = $dbh->prepare(<<'SQL') or die;
SELECT kcu.COLNAME, kcu.CONSTNAME, kcu.COLSEQ
FROM SYSCAT.TABCONST as tc
JOIN SYSCAT.KEYCOLUSE as kcu ON tc.CONSTNAME = kcu.CONSTNAME
WHERE tc.TABSCHEMA = ? and tc.TABNAME = ? and tc.TYPE = 'U'
SQL

    $sth->execute($self->db_schema, uc $table) or die;

    my %keydata;
    while(my $row = $sth->fetchrow_arrayref) {
        my ($col, $constname, $seq) = map { lc } @$row;
        push(@{$keydata{$constname}}, [ $seq, $col ]);
    }
    foreach my $keyname (keys %keydata) {
        my @ordered_cols = map { $_->[1] } sort { $a->[0] <=> $b->[0] }
            @{$keydata{$keyname}};
        push(@uniqs, { $keyname => \@ordered_cols });
    }
    $sth->finish;
    
    return \@uniqs;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
