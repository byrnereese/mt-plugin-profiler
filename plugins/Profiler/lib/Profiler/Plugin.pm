package Profiler::Plugin;

use strict;
use MT::BuildProfiler;
use Time::HiRes qw( tv_interval gettimeofday );

sub itemset_profile {
    my $app = shift;
    my $q = $app->{query};
    $app->validate_magic or return $app->error("Invalid magic");
    my @tmpls = $q->param('id');
    for my $tmpl_id (@tmpls) {
        my $tmpl = MT->model('template')->load($tmpl_id) 
	    or return $app->error( "Unable to load template #" . $tmpl_id );
	MT->log({ blog_id => $app->blog->id, message => "Profiling template: " . $tmpl->name });
	return results($app, $tmpl);
    }
}

sub results {
    my $app = shift;
    my ($tmpl) = @_;
    my $blog = $app->blog;

    require MT::Template::Context;
    require MT::Template::ContextHandlers;
    require MT::Builder;
    require MT::Util;

    $ENV{DOD_PROFILE} = 1;
    $Data::ObjectDriver::PROFILE = 1;
    MT::BuildProfiler->install;

    my $d = MT::Object->driver->r_handle;
    $d->{RaiseError} = 1;

    my $template = $tmpl->text;
    my $ctx = MT::Template::Context->new;

    my $builder = MT::Builder->new;
    $template = $app->translate_templatized($template);

    my $tokens = $builder->compile($ctx, $template);

    my $archive_type;
    # determine archive type for this template
    if ( $tmpl->type eq 'category' ) {
	$archive_type = 'Category';
    }
    elsif ( $tmpl->type eq 'individual' ) {
	$archive_type = 'Individual';
    }
    elsif ( $tmpl->type eq 'page' ) {
	$archive_type = 'Page';
    }
    elsif ( $tmpl->type eq 'archive' ) {
	my $map = MT->model('templatemap')->load( { template_id => $tmpl->id, is_preferred => 1 });
	$archive_type = $map->archive_type if $map;
    }

    $ctx->stash('blog', $app->blog);
    $ctx->stash('blog_id', $app->blog->id);

    my $e;
    if (defined $archive_type) {
	MT->log({ blog_id => $app->blog->id, message => 'Initializing: ' . $archive_type });
	my $t = $app->publisher->archiver($archive_type)
	    or return $app->error("Invalid archive type '$archive_type'");

	$ctx->{current_archive_type} = $archive_type;
	$ctx->{archive_type} = $archive_type;

	$e = load_entry( $app->blog, $t->entry_class );

	require MT::Promise;
	if ($t->date_based) {
	    my ($ts_start, $ts_end) = $t->date_range($e->authored_on);
	    $ctx->{current_timestamp} = $ts_start;
	    $ctx->{current_timestamp_end} = $ts_end;
	    my $entries = sub { $t->dated_group_entries($ctx, $archive_type, $ts_start) };
	    $ctx->stash('entries', MT::Promise::delay($entries));
	}
	if ($t->author_based) {
	    my $a = $e->author || load_author($app);
	    $ctx->stash('author') = $a;
	    my $entries = sub { $t->archive_group_entries($ctx) };
	    $ctx->stash('entries', MT::Promise::delay($entries));
	}
	if ($t->category_based) {
	    my $cat = load_category($app);
	    $ctx->stash('archive_category', $cat);
	    my $entries = sub { $t->archive_group_entries($ctx) };
	    $ctx->stash('entries', MT::Promise::delay($entries));
	}
	if ($t->entry_based) {
	    $ctx->stash('entry', $e);
	}
    }
    else {
        if (defined $archive_type) {
            return $app->error("Cannot specify archive type without a blog.");
        }
    }

    if ($ENV{DOD_PROFILE}) {
        Data::ObjectDriver->profiler->reset;
    }

    my $start = [ gettimeofday ];
    my $out = $builder->build($ctx, $tokens, {});
    my $end = [ gettimeofday ];

    my $param ||= {};
    return $app->error("Builder error: ".$builder->errstr) if $builder->errstr;
    return $app->error("Context error: ".$ctx->errstr) if $ctx->errstr;
    my @rows = MT::BuildProfiler->report();

    $param->{rows} = \@rows;
    $param->{template_name} = $tmpl->name;
    $param->{total_time} = tv_interval($start, $end);

    return $app->load_tmpl( 'report.tmpl', $param );
}

sub load_category {
    my $app = shift;

    my $cat;
#    if ($category_name =~ m/^\d+$/) {
#        $cat = MT->model('category')->load($category_name)
#            or die "Could not load category # $category_name";
#    }
#    elsif (defined $category_name) {
#        $cat = MT::Category->load({
#            label => $category_name,
#            ( $blog ? ( blog_id => $blog->id ) : () ),
#        }) or die "Could not locate category by name '$category_name'";
#    }
#    else {
        # okay, select first available
	my $c = '= placement_entry_id';
        my $p = MT->model('placement')->load({
            ( $app->blog ? ( blog_id => $app->blog->id ) : () ),
            is_primary => 1,
            },
            { limit => 1,
              join => MT->model('entry')->join_on( undef, {
                  class => 'entry',
                  id => \$c,
                  status => 2,
              } ), }
        );
        if ( $p ) {
            $cat = MT->model('category')->load( $p->category_id );
        }
#    }
    return $cat;
}

sub load_author {
    my $app = shift;

    # TODO
    my $author_name = '';
    if ($author_name =~ m/^\d+$/) {
        $a = MT->model('author')->load($author_name)
            or die "Could not load author # $author_name";
    }
    elsif (defined $author_name) {
        $a = MT->model('author')->load({ name => $author_name })
            or die "Could not locate author by name '$author_name'";
    }
    return $a;
}

sub load_entry {
    my ($app,$entry_class) = @_;

    # load first available
    my $e = MT->model('entry')->load( {
	class => $entry_class,
	status => 2,
	blog_id => $app->blog->id,
        }, { limit => 1, sort => 'authored_on', direction => 'descend' });
    return $e;
}

1;

__END__
