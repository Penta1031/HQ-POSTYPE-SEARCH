begin;

create or replace function public.postype_admin_search_stats(p_from date, p_to date, p_limit integer default 20)
returns jsonb language sql stable security definer set search_path = public as $$
  with filtered as (
    select * from public.postype_search_events
    where searched_on between least(p_from, p_to) and greatest(p_from, p_to)
  ), top_queries as (
    select query_kind, query_text, count(*)::bigint searches,
      count(distinct session_id)::bigint visitors,
      count(*) filter (where result_count = 0)::bigint zero_results,
      max(searched_at) last_searched_at
    from filtered group by query_kind, query_text
    order by searches desc, last_searched_at desc
    limit least(greatest(p_limit, 1), 20)
  ), filter_items as (
    select item->>'group' filter_group, item->>'value' filter_value,
      filtered.session_id, filtered.searched_at
    from filtered
    cross join lateral jsonb_array_elements(filtered.selected_filters) item
  ), top_filters as (
    select filter_group, filter_value, count(*)::bigint selections,
      count(distinct session_id)::bigint visitors,
      max(searched_at) last_selected_at
    from filter_items
    where filter_group <> '' and filter_value <> ''
    group by filter_group, filter_value
    order by selections desc, last_selected_at desc
    limit least(greatest(p_limit, 1), 20)
  ), recent as (
    select searched_on, query_kind, query_text, count(*)::bigint searches,
      max(searched_at) searched_at
    from filtered
    group by searched_on, query_kind, query_text
    order by searched_at desc
    limit 100
  )
  select jsonb_build_object(
    'totals', jsonb_build_object(
      'searches', (select count(*) from filtered),
      'visitors', (select count(distinct session_id) from filtered),
      'zeroResults', (select count(*) from filtered where result_count = 0)
    ),
    'top', coalesce((select jsonb_agg(to_jsonb(top_queries) order by searches desc, last_searched_at desc) from top_queries), '[]'::jsonb),
    'topFilters', coalesce((select jsonb_agg(to_jsonb(top_filters) order by selections desc, last_selected_at desc) from top_filters), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(to_jsonb(recent) order by searched_at desc) from recent), '[]'::jsonb)
  );
$$;

revoke all on function public.postype_admin_search_stats(date, date, integer) from public, anon, authenticated;
grant execute on function public.postype_admin_search_stats(date, date, integer) to service_role;

commit;
