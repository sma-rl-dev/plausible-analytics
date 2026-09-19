defmodule Plausible.TesterEnvSeed do
  import Ecto.Query

  alias Plausible.{Auth.User, Goal, Repo, Site, Teams}
  alias Plausible.Site.SharedLink
  alias Plausible.Teams.Membership
  alias Plausible.{ClickhouseEventV2, ClickhouseSessionV2, IngestRepo}

  @domain "northstar-market.test"
  @start ~N[2026-08-01 00:00:00]
  @editor_email "editor@plausible.test"
  @editor_password "PlausibleTesterEnv123!"
  @shared_link_name "Tester Env Shared Link"
  @shared_link_slug "testerenvsharedlink01"

  def seed do
    site =
      case Repo.get_by(Site, domain: @domain) do
        nil -> create_seed()
        site -> site
      end

    ensure_editor(site)
    ensure_shared_link(site)
    verify()
  end

  def verify do
    site = Repo.get_by!(Site, domain: @domain)
    2 = Repo.aggregate(from(g in Goal, where: g.site_id == ^site.id), :count)
    15 = IngestRepo.aggregate(from(e in "events_v2", where: e.site_id == ^site.id), :count)
    12 = IngestRepo.aggregate(from(s in "sessions_v2", where: s.site_id == ^site.id), :count)

    [{"Direct", 4}, {"GitHub", 3}, {"Google", 5}] =
      IngestRepo.all(
        from(s in "sessions_v2",
          where: s.site_id == ^site.id,
          group_by: s.referrer_source,
          select: {s.referrer_source, count(s.session_id)},
          order_by: s.referrer_source
        )
      )

    editor = Repo.get_by!(User, email: @editor_email)
    %Membership{role: :editor} = Repo.get_by!(Membership, team_id: site.team_id, user_id: editor.id)
    %SharedLink{} = Repo.get_by!(SharedLink, site_id: site.id, slug: @shared_link_slug)

    IO.puts("verified #{@domain}: 12 sessions, 12 pageviews, 3 signups, 2 goals")
    IO.puts("verified #{@domain}: editor #{@editor_email} is team :editor, 1 shared link #{@shared_link_slug}")
    :ok
  end

  defp create_seed do
    user = Repo.get_by!(User, email: System.fetch_env!("ADMIN_EMAIL"))
    {:ok, team} = Teams.get_or_create(user)

    site =
      team
      |> Site.new_for_team(%{domain: @domain, timezone: "Etc/UTC"})
      |> Repo.insert!()
      |> Ecto.Changeset.change(native_stats_start_at: @start, stats_start_date: ~D[2026-08-01])
      |> Repo.update!()

    {:ok, _} = Plausible.Goals.create(site, %{"page_path" => "/checkout/complete", "display_name" => "Completed checkout"})
    {:ok, _} = Plausible.Goals.create(site, %{"event_name" => "Newsletter Signup", "display_name" => "Newsletter signup"})

    visits = [
      {"/", "Google", "google", "Organic Search"},
      {"/products/aurora-lamp", "Google", "google", "Organic Search"},
      {"/products/aurora-lamp", "Google", "google", "Organic Search"},
      {"/checkout", "Google", "google", "Organic Search"},
      {"/checkout/complete", "Google", "google", "Organic Search"},
      {"/", "GitHub", "github.com", "Referral"},
      {"/products/aurora-lamp", "GitHub", "github.com", "Referral"},
      {"/newsletter", "GitHub", "github.com", "Referral"},
      {"/", "Direct", "", ""},
      {"/shipping", "Direct", "", ""},
      {"/checkout/complete", "Direct", "", ""},
      {"/checkout/complete", "Direct", "", ""}
    ]

    sessions =
      visits
      |> Enum.with_index(1)
      |> Enum.map(fn {{path, source, utm_source, _medium}, index} ->
        session(site.id, index, path, source, utm_source)
      end)

    pageviews =
      visits
      |> Enum.with_index(1)
      |> Enum.map(fn {{path, source, utm_source, _medium}, index} ->
        event(site.id, index, path, "pageview", source, utm_source)
      end)

    signups =
      for index <- [3, 7, 10] do
        {path, source, utm_source, _} = Enum.at(visits, index - 1)
        event(site.id, index, path, "Newsletter Signup", source, utm_source)
      end

    {12, _} = IngestRepo.insert_all(ClickhouseSessionV2, sessions)
    {15, _} = IngestRepo.insert_all(ClickhouseEventV2, pageviews ++ signups)
    site
  end

  # A team-member :editor covers both the change-domain scenario (site editors
  # may open the change-domain page) and the subscription-visibility scenario
  # (only :owner/:billing team roles see the Subscription menu entry), so no
  # separate viewer user is needed.
  defp ensure_editor(site) do
    editor =
      case Repo.get_by(User, email: @editor_email) do
        nil ->
          Repo.insert!(
            User.new(%{
              email: @editor_email,
              name: "Tester Env Editor",
              password: @editor_password,
              password_confirmation: @editor_password
            })
          )

        user ->
          user
      end

    team = Repo.get!(Teams.Team, site.team_id)

    case Repo.get_by(Membership, team_id: team.id, user_id: editor.id) do
      nil ->
        Repo.insert!(Membership.changeset(team, editor, :editor))

      %Membership{role: :editor} = membership ->
        membership

      membership ->
        membership |> Ecto.Changeset.change(role: :editor) |> Repo.update!()
    end
  end

  defp ensure_shared_link(site) do
    case Repo.get_by(SharedLink, site_id: site.id, slug: @shared_link_slug) do
      nil ->
        %SharedLink{site_id: site.id, slug: @shared_link_slug}
        |> SharedLink.changeset(%{name: @shared_link_name})
        |> Repo.insert!()

      link ->
        link
    end
  end

  defp session(site_id, index, path, source, utm_source) do
    timestamp = timestamp(index)

    %{
      site_id: site_id, user_id: 1000 + index, session_id: 2000 + index, hostname: @domain,
      timestamp: timestamp, start: timestamp, is_bounce: true, entry_page: path, exit_page: path,
      exit_page_hostname: @domain, pageviews: 1, events: if(index in [3, 7, 10], do: 1, else: 0),
      duration: 45, sign: 1, referrer: if(source == "Direct", do: "", else: "https://#{utm_source}/"),
      referrer_source: source, country_code: "US", screen_size: "Desktop", operating_system: "Mac",
      browser: "Chrome", utm_medium: "", utm_source: utm_source, utm_campaign: "",
      browser_version: "128", operating_system_version: "14", subdivision1_code: "US-CA",
      subdivision2_code: "", city_geoname_id: 5_391_959, utm_content: "", utm_term: "",
      transferred_from: "", "entry_meta.key": [], "entry_meta.value": []
    }
  end

  defp event(site_id, index, path, name, source, utm_source) do
    %{
      site_id: site_id, user_id: 1000 + index, session_id: 2000 + index, hostname: @domain,
      timestamp: NaiveDateTime.add(timestamp(index), if(name == "pageview", do: 0, else: 15)),
      name: name, pathname: path, referrer: if(source == "Direct", do: "", else: "https://#{utm_source}/"),
      referrer_source: source, country_code: "US", screen_size: "Desktop", operating_system: "Mac",
      browser: "Chrome", utm_medium: "", utm_source: utm_source, utm_campaign: "",
      "meta.key": [], "meta.value": [], browser_version: "128", operating_system_version: "14",
      subdivision1_code: "US-CA", subdivision2_code: "", city_geoname_id: 5_391_959,
      utm_content: "", utm_term: "", revenue_reporting_amount: nil, revenue_reporting_currency: "",
      revenue_source_amount: nil, revenue_source_currency: "", click_id_param: "", scroll_depth: 0,
      engagement_time: 0
    }
  end

  defp timestamp(index), do: NaiveDateTime.add(~N[2026-08-12 09:00:00], index * 3_600)
end
