package DBIx::Class::Schema::Loader::DBI;

use strict;
use warnings;
use base qw/DBIx::Class::Schema::Loader::Base Class::Accessor::Fast/;
use Class::C3;
use Carp;
use UNIVERSAL::require;

=head1 NAME

DBIx::Class::Schema::Loader::DBI - DBIx::Class::Schema::Loader DBI Implementation.

=head1 SYNOPSIS

See L<DBIx::Class::Schema::Loader::Base>

=head1 DESCRIPTION

This is the base class for L<DBIx::Class::Schema::Loader> DBI-based storage
backends and implements the common functionality between them.

See L<DBIx::Class::Schema::Loader::Base> for the available options.

=head1 METHODS

=head2 new

Overlays L<DBIx::Class::Schema::Loader::Base/new> to add support for
deprecated connect_info and dsn/user/password/options args, and to
rebless into a vendor class if neccesary.

=cut

sub new {
    my $self = shift->next::method(@_);

    # Support deprecated connect_info and dsn args
    if($self->{connect_info}) {
        warn "Argument connect_info is deprecated";
        $self->schema->connection(@{$self->{connect_info}});
    }
    elsif($self->{dsn}) {
        warn "Arguments dsn, user, password, and options are deprecated";
        $self->schema->connection(
            $self->{dsn},
            $self->{user},
            $self->{password},
            $self->{options},
        );
    }

    # rebless to vendor-specific class if it exists and loads
    my $dbh = $self->schema->storage->dbh;
    my $driver = $dbh->{Driver}->{Name};
    my $subclass = 'DBIx::Class::Schema::Loader::DBI::' . $driver;
    $subclass->require;
    if($@ && $@ !~ /^Can't locate /) {
        die "Failed to require $subclass: $@";
    }
    elsif(!$@) {
        bless $self, "DBIx::Class::Schema::Loader::DBI::${driver}";
    }

    $self->{_quoter} = $self->schema->storage->sql_maker->quote_char
                    || $dbh->get_info(29)
                    || q{"};

    $self->{_namesep} = $self->schema->storage->sql_maker->name_sep
                     || $dbh->get_info(41)
                     || q{.};

    if( ref $self->{_quoter} eq 'ARRAY') {
        $self->{_quoter} = join(q{}, @{$self->{_quoter}});
    }

    $self->_setup;

    $self;
}

# Override this in vendor modules to do things at the end of ->new()
sub _setup { }

# Returns an array of table names
sub _tables_list { 
    my $self = shift;

    my $dbh = $self->schema->storage->dbh;
    my $db_schema = $self->db_schema;
    my @tables = $dbh->tables(undef, $db_schema, '%', '%');
    s/\Q$self->{_quoter}\E//g for @tables;
    s/^.*\Q$self->{_namesep}\E// for @tables;

    return map { lc } @tables;
}

# Returns a hash ( col1name => { is_nullable => 1 }, ... )
sub _table_columns_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my @result;
    if ( $dbh->can( 'column_info' ) && !$self->{_column_info_broken}){
        my $sth = $dbh->column_info( undef, $self->db_schema || undef, $table, '%' );
        $sth->execute();
        while ( my $info = $sth->fetchrow_hashref() ){
            my %column_info;
            # XXX attempt to translate numeric data_type ?
            $column_info{data_type} = $info->{TYPE_NAME};
            $column_info{size} = $info->{COLUMN_SIZE};
            $column_info{is_nullable} = $info->{NULLABLE} ? 1 : 0;
            $column_info{default_value} = $info->{COLUMN_DEF};
            push(@result, lc $info->{COLUMN_NAME}, \%column_info);
        }
    } else {
        my $sth = $dbh->prepare("SELECT * FROM $table WHERE 1=0");
        $sth->execute;
        my @columns = @{$sth->{NAME_lc}};
        for my $i ( 0 .. $#columns ){
            my %column_info;
            $column_info{data_type} = $sth->{TYPE}->[$i];
            $column_info{size} = $sth->{PRECISION}->[$i];
            $column_info{is_nullable} = $sth->{NULLABLE}->[$i] ? 1 : 0;
            push(@result, $columns[$i], \%column_info);
        }
    }

    return @result;
}

# Returns arrayref of pk col names
sub _table_pk_info { 
    my ( $self, $table ) = @_;

    my $dbh = $self->schema->storage->dbh;

    my @primary = map { lc } $dbh->primary_key('', $self->db_schema, $table);
    s/\Q$self->{_quoter}\E//g for @primary;

    return \@primary;
}

# Override this for uniq info
sub _table_uniq_info { [] } # XXX croak "ABSTRACT METHOD" ?? 

# Find relationships
sub _table_fk_info {
    my ($self, $table) = @_;

    my $dbh = $self->schema->storage->dbh;
    my $sth = $dbh->foreign_key_info( '',
        $self->db_schema, '', '', '', $table );
    return [] if !$sth;

    my %rels;

    my $i = 1; # for unnamed rels, which hopefully have only 1 column ...
    while(my $raw_rel = $sth->fetchrow_arrayref) {
        my $uk_tbl  = lc $raw_rel->[2];
        my $uk_col  = lc $raw_rel->[3];
        my $fk_col  = lc $raw_rel->[7];
        my $relid   = lc ($raw_rel->[12] || ( "__dcsld__" . $i++ ));
        $uk_tbl =~ s/\Q$self->{_quoter}\E//g;
        $uk_col =~ s/\Q$self->{_quoter}\E//g;
        $fk_col =~ s/\Q$self->{_quoter}\E//g;
        $relid  =~ s/\Q$self->{_quoter}\E//g;
        $rels{$relid}->{tbl} = $uk_tbl;
        $rels{$relid}->{cols}->{$uk_col} = $fk_col;
    }

    my @rels;
    foreach my $relid (keys %rels) {
        push(@rels, {
            remote_columns => [ keys   %{$rels{$relid}->{cols}} ],
            local_columns  => [ values %{$rels{$relid}->{cols}} ],
            remote_table   => $rels{$relid}->{tbl},
        });
    }

    return \@rels;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;