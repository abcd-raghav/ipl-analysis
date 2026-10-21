-- =====================================================================
-- IPL Match & Player Performance Analysis  |  SQL analysis (PostgreSQL)
-- Tables: matches, deliveries, teams, players
-- Business question: Which teams, venues and players win the most?
-- Note: super overs (inning > 2) are excluded from player statistics.
-- =====================================================================


-- Q1. Team wins and win percentage  [CTE + JOIN + GROUP BY]
-- Why: answers "which teams win most". Ties are counted (decided by super over).
WITH played AS (
    SELECT team1 AS team, id FROM matches WHERE is_completed = 1
    UNION ALL
    SELECT team2 AS team, id FROM matches WHERE is_completed = 1
),
matches_played AS (
    SELECT team, COUNT(*) AS played FROM played GROUP BY team
),
wins AS (
    SELECT winner AS team, COUNT(*) AS wins
    FROM matches WHERE winner <> 'No Result' GROUP BY winner
)
SELECT t.team_name,
       mp.played,
       COALESCE(w.wins, 0) AS wins,
       ROUND(100.0 * COALESCE(w.wins, 0) / mp.played, 2) AS win_pct
FROM teams t
JOIN matches_played mp ON mp.team = t.team_name
LEFT JOIN wins w ON w.team = t.team_name
ORDER BY wins DESC;


-- Q2. Does winning the toss help?  [GROUP BY + CASE]
SELECT toss_decision,
       COUNT(*) AS matches,
       SUM(CASE WHEN toss_winner = winner THEN 1 ELSE 0 END) AS toss_winner_won,
       ROUND(100.0 * SUM(CASE WHEN toss_winner = winner THEN 1 ELSE 0 END) / COUNT(*), 2) AS toss_win_to_match_win_pct
FROM matches
WHERE is_completed = 1
GROUP BY toss_decision;


-- Q3. Venue profile: matches, average first-innings score, bat-first win %  [CTE + JOIN]
WITH first_innings AS (
    SELECT match_id, batting_team, SUM(total_runs) AS score
    FROM deliveries
    WHERE inning = 1
    GROUP BY match_id, batting_team
)
SELECT m.venue,
       COUNT(*) AS matches,
       ROUND(AVG(f.score), 1) AS avg_first_innings_score,
       ROUND(100.0 * SUM(CASE WHEN m.winner = f.batting_team THEN 1 ELSE 0 END) / COUNT(*), 1) AS bat_first_win_pct
FROM matches m
JOIN first_innings f ON f.match_id = m.id
WHERE m.is_completed = 1
GROUP BY m.venue
HAVING COUNT(*) >= 20
ORDER BY avg_first_innings_score DESC;


-- Q4. Most successful team at each venue (venues with 20+ matches)  [window function]
WITH venue_wins AS (
    SELECT venue, winner AS team, COUNT(*) AS wins
    FROM matches
    WHERE winner <> 'No Result'
    GROUP BY venue, winner
),
ranked AS (
    SELECT venue, team, wins,
           ROW_NUMBER() OVER (PARTITION BY venue ORDER BY wins DESC) AS rn
    FROM venue_wins
)
SELECT r.venue, r.team AS best_team, r.wins
FROM ranked r
WHERE r.rn = 1
  AND r.venue IN (SELECT venue FROM matches GROUP BY venue HAVING COUNT(*) >= 20)
ORDER BY r.wins DESC;


-- Q5. Batting first vs chasing: who wins more?  [CTE + JOIN]
WITH first_innings AS (
    SELECT match_id, batting_team FROM deliveries WHERE inning = 1 GROUP BY match_id, batting_team
)
SELECT CASE WHEN m.winner = f.batting_team THEN 'Batting first won' ELSE 'Chasing team won' END AS outcome,
       COUNT(*) AS matches,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM matches m
JOIN first_innings f ON f.match_id = m.id
WHERE m.is_completed = 1
GROUP BY CASE WHEN m.winner = f.batting_team THEN 'Batting first won' ELSE 'Chasing team won' END;


-- Q6. Top 10 run scorers with strike rate  [JOIN + GROUP BY]
SELECT p.player_name,
       COUNT(DISTINCT d.match_id) AS matches,
       SUM(d.batsman_runs) AS total_runs,
       SUM(d.ball_faced) AS balls_faced,
       ROUND(100.0 * SUM(d.batsman_runs) / SUM(d.ball_faced), 2) AS strike_rate
FROM deliveries d
JOIN players p ON p.player_name = d.batter
JOIN matches m ON m.id = d.match_id
WHERE d.is_super_over = 0
GROUP BY p.player_name
ORDER BY total_runs DESC
LIMIT 10;


-- Q7. Top 10 wicket takers with economy rate (min. 500 legal balls)  [JOIN + HAVING]
SELECT p.player_name,
       SUM(d.bowler_wicket) AS wickets,
       SUM(d.is_legal_ball) AS legal_balls,
       ROUND(6.0 * SUM(d.bowler_runs) / SUM(d.is_legal_ball), 2) AS economy
FROM deliveries d
JOIN players p ON p.player_name = d.bowler
WHERE d.is_super_over = 0
GROUP BY p.player_name
HAVING SUM(d.is_legal_ball) >= 500
ORDER BY wickets DESC
LIMIT 10;


-- Q8. Most Player of the Match awards  [JOIN + GROUP BY]
SELECT p.player_name, COUNT(*) AS awards
FROM matches m
JOIN players p ON p.player_name = m.player_of_match
GROUP BY p.player_name
ORDER BY awards DESC
LIMIT 10;


-- Q9. IPL titles by team  [subquery in FROM]
SELECT f.winner AS team, COUNT(*) AS titles
FROM (
    SELECT season, winner FROM matches WHERE match_type = 'Final'
) f
GROUP BY f.winner
ORDER BY titles DESC;


-- Q10. Highest run scorer for every team  [4-table JOIN + window function]
WITH team_runs AS (
    SELECT t.team_name, p.player_name, SUM(d.batsman_runs) AS runs
    FROM deliveries d
    JOIN matches m ON m.id = d.match_id
    JOIN players p ON p.player_name = d.batter
    JOIN teams t   ON t.team_name = d.batting_team
    WHERE d.is_super_over = 0
    GROUP BY t.team_name, p.player_name
),
ranked AS (
    SELECT team_name, player_name, runs,
           RANK() OVER (PARTITION BY team_name ORDER BY runs DESC) AS rnk
    FROM team_runs
)
SELECT team_name, player_name, runs
FROM ranked
WHERE rnk = 1
ORDER BY runs DESC;
