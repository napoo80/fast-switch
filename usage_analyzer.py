#!/usr/bin/env python3
"""
FastSwitch Usage Data Analyzer v2.0 - With Wellness Analysis

This script analyzes the exported usage data from FastSwitch and generates detailed insights.

USAGE:
    python3 usage_analyzer.py <path_to_exported_json> [options]

OPTIONS:
    --summary           Show summary only
    --wellness-only     Show only wellness analysis  
    --correlations      Show only correlation analysis
    --days N           Analyze only last N days

EXAMPLES:
    python3 usage_analyzer.py FastSwitch-Usage-Data-2024-08-14.json
    python3 usage_analyzer.py data.json --wellness-only
    python3 usage_analyzer.py data.json --days 7 --correlations

REQUIREMENTS:
    - Python 3.6+
    - JSON file exported from FastSwitch (Menu → Reportes → Exportar Datos)

OUTPUT:
    - 📊 Total work time, break time, call time statistics
    - 📱 Top applications with usage percentages
    - 🌱 Wellness metrics: mate consumption, exercise, energy levels
    - 📝 Mood analysis and daily reflections
    - 🔗 Wellness-productivity correlations and insights
    - Deep Focus session analysis
    - Work pattern insights (longest sessions, averages)
    - Weekly productivity patterns
    - Monthly/yearly breakdowns
"""

import json
import sys
from datetime import datetime, timedelta
from collections import defaultdict
import argparse

def parse_date(date_str):
    """Parse ISO date string to datetime object"""
    return datetime.fromisoformat(date_str.replace('Z', '+00:00'))

def format_duration(seconds):
    """Format duration in seconds to human readable format"""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    if hours > 0:
        return f"{hours}h {minutes}m"
    else:
        return f"{minutes}m"

def analyze_usage_data(data):
    """Analyze the usage data and generate insights"""
    daily_data = data.get('dailyData', {})
    
    if not daily_data:
        print("No usage data found in the file.")
        return
    
    print("📊 FastSwitch Usage Analysis")
    print("=" * 50)
    
    # Basic statistics
    total_days = len(daily_data)
    total_session_time = sum(day['totalSessionTime'] for day in daily_data.values())
    total_break_time = sum(day['totalBreakTime'] for day in daily_data.values())
    total_call_time = sum(day['callTime'] for day in daily_data.values())
    
    print(f"\n📅 Data Range: {total_days} days")
    print(f"⏰ Total Work Time: {format_duration(total_session_time)}")
    print(f"☕ Total Break Time: {format_duration(total_break_time)}")
    print(f"📞 Total Call Time: {format_duration(total_call_time)}")
    
    if total_days > 0:
        avg_daily_work = total_session_time / total_days
        print(f"📈 Average Daily Work: {format_duration(avg_daily_work)}")
    
    # App usage analysis
    app_usage = defaultdict(float)
    for day in daily_data.values():
        for app, time in day.get('appUsage', {}).items():
            app_usage[app] += time
    
    if app_usage:
        print(f"\n📱 Top Applications:")
        sorted_apps = sorted(app_usage.items(), key=lambda x: x[1], reverse=True)
        for i, (app, time) in enumerate(sorted_apps[:10], 1):
            # Simplify app names
            app_name = app.split('.')[-1] if '.' in app else app
            percentage = (time / total_session_time) * 100 if total_session_time > 0 else 0
            print(f"  {i:2d}. {app_name:20s}: {format_duration(time):>8s} ({percentage:4.1f}%)")
    
    # Deep Focus analysis
    deep_focus_sessions = []
    for day in daily_data.values():
        deep_focus_sessions.extend(day.get('deepFocusSessions', []))
    
    if deep_focus_sessions:
        total_focus_time = sum(session['duration'] for session in deep_focus_sessions)
        avg_session_length = total_focus_time / len(deep_focus_sessions)
        print(f"\n🧘 Deep Focus Statistics:")
        print(f"   Sessions: {len(deep_focus_sessions)}")
        print(f"   Total Time: {format_duration(total_focus_time)}")
        print(f"   Average Session: {format_duration(avg_session_length)}")
    
    # Work pattern analysis
    continuous_sessions = []
    for day in daily_data.values():
        continuous_sessions.extend(day.get('continuousWorkSessions', []))
    
    if continuous_sessions:
        longest_session = max(session['duration'] for session in continuous_sessions)
        avg_session = sum(session['duration'] for session in continuous_sessions) / len(continuous_sessions)
        print(f"\n💪 Work Patterns:")
        print(f"   Continuous Sessions: {len(continuous_sessions)}")
        print(f"   Longest Session: {format_duration(longest_session)}")
        print(f"   Average Session: {format_duration(avg_session)}")
    
    # Weekly patterns
    if total_days >= 7:
        print(f"\n📅 Weekly Patterns:")
        weekly_totals = defaultdict(float)
        for date_str, day in daily_data.items():
            date_obj = datetime.strptime(date_str, '%Y-%m-%d')
            weekday = date_obj.strftime('%A')
            weekly_totals[weekday] += day['totalSessionTime']
        
        days_order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
        for day in days_order:
            if day in weekly_totals:
                avg_time = weekly_totals[day] / (total_days // 7 + (1 if total_days % 7 > days_order.index(day) else 0))
                print(f"   {day:9s}: {format_duration(avg_time)}")

def analyze_wellness_data(daily_data):
    """Analyze wellness and health-related metrics"""
    print(f"\n🌱 WELLNESS & HEALTH ANALYSIS")
    print("=" * 50)
    
    mate_records = []
    exercise_records = []
    energy_records = []
    mood_records = []
    reflection_days = 0
    
    # Collect wellness data
    for day_data in daily_data.values():
        wellness = day_data.get('wellnessMetrics', {})
        
        # Mate/Sugar data
        mate_data = wellness.get('mateAndSugarRecords', [])
        mate_records.extend(mate_data)
        
        # Exercise data
        exercise_data = wellness.get('exerciseRecords', [])
        exercise_records.extend(exercise_data)
        
        # Energy checks
        energy_data = wellness.get('energyChecks', [])
        energy_records.extend(energy_data)
        
        # Daily reflections
        if wellness.get('dailyReflection'):
            reflection_days += 1
            reflection = wellness['dailyReflection']
            mood_records.append({
                'mood': reflection.get('mood', ''),
                'energy': reflection.get('energyLevel', 0),
                'stress': reflection.get('stressLevel', 0),
                'quality': reflection.get('workQuality', '')
            })
    
    # Mate & Sugar Analysis
    if mate_records:
        print(f"\n🧉 Mate & Sugar Consumption:")
        total_mate = sum(record.get('mateAmount', 0) for record in mate_records)
        total_sugar = sum(record.get('sugarLevel', 0) for record in mate_records)
        avg_mate_per_check = total_mate / len(mate_records) if mate_records else 0
        avg_sugar_per_check = total_sugar / len(mate_records) if mate_records else 0
        
        print(f"   Total Reports: {len(mate_records)}")
        print(f"   Avg Mate per Check: {avg_mate_per_check:.1f}")
        print(f"   Avg Sugar Level: {avg_sugar_per_check:.1f}")
        
        # Mate reduction tracking
        daily_mate_totals = {}
        for record in mate_records:
            date = record.get('timestamp', '')[:10]  # Extract date
            if date:
                daily_mate_totals[date] = daily_mate_totals.get(date, 0) + record.get('mateAmount', 0)
        
        if len(daily_mate_totals) > 1:
            mate_values = list(daily_mate_totals.values())
            print(f"   Trend: {'📉 Reducing' if mate_values[-1] < mate_values[0] else '📈 Increasing'}")
    
    # Exercise Analysis
    if exercise_records:
        print(f"\n🏃 Exercise Tracking:")
        exercise_days = sum(1 for record in exercise_records if record.get('done', False))
        total_duration = sum(record.get('duration', 0) for record in exercise_records if record.get('done', False))
        
        print(f"   Total Reports: {len(exercise_records)}")
        print(f"   Exercise Days: {exercise_days}")
        print(f"   Success Rate: {(exercise_days/len(exercise_records)*100):.1f}%")
        if exercise_days > 0:
            print(f"   Avg Duration: {total_duration/exercise_days:.0f} minutes")
        
        # Exercise intensity distribution
        intensity_count = {'none': 0, 'light': 0, 'moderate': 0, 'intense': 0}
        for record in exercise_records:
            exercise_type = record.get('type', 'none')
            intensity_count[exercise_type] = intensity_count.get(exercise_type, 0) + 1
        
        print(f"   Intensity Distribution:")
        for intensity, count in intensity_count.items():
            if count > 0:
                print(f"     {intensity.capitalize()}: {count} days")
    
    # Energy Level Analysis
    if energy_records:
        print(f"\n⚡ Energy Level Tracking:")
        avg_energy = sum(record.get('energyLevel', 0) for record in energy_records) / len(energy_records)
        print(f"   Total Reports: {len(energy_records)}")
        print(f"   Average Energy: {avg_energy:.1f}/10")
        
        # Energy distribution
        energy_levels = [record.get('energyLevel', 0) for record in energy_records]
        low_energy_days = sum(1 for level in energy_levels if level <= 4)
        high_energy_days = sum(1 for level in energy_levels if level >= 7)
        
        print(f"   Low Energy Days (≤4): {low_energy_days}")
        print(f"   High Energy Days (≥7): {high_energy_days}")
    
    # Mood & Reflection Analysis
    if mood_records:
        print(f"\n📝 Mood & Reflection Analysis:")
        print(f"   Reflection Days: {reflection_days}")
        
        # Mood distribution
        mood_count = {}
        total_energy = 0
        total_stress = 0
        
        for record in mood_records:
            mood = record['mood']
            mood_count[mood] = mood_count.get(mood, 0) + 1
            total_energy += record['energy']
            total_stress += record['stress']
        
        print(f"   Mood Distribution:")
        for mood, count in mood_count.items():
            print(f"     {mood.capitalize()}: {count} days")
        
        if mood_records:
            avg_energy = total_energy / len(mood_records)
            avg_stress = total_stress / len(mood_records)
            print(f"   Average Energy (reflection): {avg_energy:.1f}/10")
            print(f"   Average Stress: {avg_stress:.1f}/10")
        
        # Work quality correlation
        quality_count = {}
        for record in mood_records:
            quality = record['quality']
            quality_count[quality] = quality_count.get(quality, 0) + 1
        
        print(f"   Work Quality Distribution:")
        for quality, count in quality_count.items():
            print(f"     {quality.capitalize()}: {count} days")

def analyze_correlations(daily_data):
    """Analyze correlations between wellness metrics and productivity"""
    print(f"\n🔗 WELLNESS-PRODUCTIVITY CORRELATIONS")
    print("=" * 50)
    
    correlations = []
    
    for day_data in daily_data.values():
        wellness = day_data.get('wellnessMetrics', {})
        session_time = day_data.get('totalSessionTime', 0)
        
        # Daily totals
        mate_total = sum(record.get('mateAmount', 0) for record in wellness.get('mateAndSugarRecords', []))
        exercise_done = any(record.get('done', False) for record in wellness.get('exerciseRecords', []))
        avg_energy = sum(record.get('energyLevel', 0) for record in wellness.get('energyChecks', [])) / max(len(wellness.get('energyChecks', [])), 1)
        
        reflection = wellness.get('dailyReflection', {})
        mood_score = {'productive': 4, 'balanced': 3, 'tired': 2, 'stressed': 1}.get(reflection.get('mood', 'balanced'), 3)
        
        correlations.append({
            'session_time': session_time,
            'mate_total': mate_total,
            'exercise_done': exercise_done,
            'avg_energy': avg_energy,
            'mood_score': mood_score
        })
    
    if len(correlations) >= 3:  # Need at least 3 data points for meaningful analysis
        print(f"   Analyzed {len(correlations)} days of data:\n")
        
        # Simple correlation insights
        high_productivity_days = [day for day in correlations if day['session_time'] > sum(d['session_time'] for d in correlations) / len(correlations)]
        low_productivity_days = [day for day in correlations if day['session_time'] < sum(d['session_time'] for d in correlations) / len(correlations) * 0.7]
        
        if high_productivity_days:
            avg_mate_high = sum(day['mate_total'] for day in high_productivity_days) / len(high_productivity_days)
            avg_energy_high = sum(day['avg_energy'] for day in high_productivity_days) / len(high_productivity_days)
            exercise_rate_high = sum(day['exercise_done'] for day in high_productivity_days) / len(high_productivity_days) * 100
            
            print(f"   📈 High Productivity Days ({len(high_productivity_days)} days):")
            print(f"      Average Mate Consumption: {avg_mate_high:.1f}")
            print(f"      Average Energy Level: {avg_energy_high:.1f}/10")
            print(f"      Exercise Rate: {exercise_rate_high:.0f}%")
        
        if low_productivity_days:
            avg_mate_low = sum(day['mate_total'] for day in low_productivity_days) / len(low_productivity_days)
            avg_energy_low = sum(day['avg_energy'] for day in low_productivity_days) / len(low_productivity_days)
            exercise_rate_low = sum(day['exercise_done'] for day in low_productivity_days) / len(low_productivity_days) * 100
            
            print(f"\n   📉 Low Productivity Days ({len(low_productivity_days)} days):")
            print(f"      Average Mate Consumption: {avg_mate_low:.1f}")
            print(f"      Average Energy Level: {avg_energy_low:.1f}/10")
            print(f"      Exercise Rate: {exercise_rate_low:.0f}%")
            
            # Insights
            print(f"\n   💡 Insights:")
            if avg_energy_high > avg_energy_low + 1:
                print(f"      ⚡ Higher energy correlates with better productivity")
            if exercise_rate_high > exercise_rate_low + 20:
                print(f"      🏃 Exercise appears to boost productivity")
            if abs(avg_mate_high - avg_mate_low) > 1:
                if avg_mate_high > avg_mate_low:
                    print(f"      🧉 Higher mate consumption on productive days")
                else:
                    print(f"      🧉 Lower mate consumption on productive days")

def main():
    parser = argparse.ArgumentParser(description='Analyze FastSwitch usage data')
    parser.add_argument('file', help='Path to the exported JSON file')
    parser.add_argument('--summary', action='store_true', help='Show summary only')
    parser.add_argument('--wellness-only', action='store_true', help='Show only wellness analysis')
    parser.add_argument('--correlations', action='store_true', help='Show only correlation analysis')
    parser.add_argument('--days', type=int, help='Analyze only last N days')
    
    args = parser.parse_args()
    
    try:
        with open(args.file, 'r') as f:
            data = json.load(f)
        
        daily_data = data.get('dailyData', {})
        
        # Filter by days if specified
        if args.days:
            from datetime import datetime, timedelta
            cutoff_date = datetime.now() - timedelta(days=args.days)
            filtered_daily_data = {
                date_str: day_data for date_str, day_data in daily_data.items()
                if datetime.strptime(date_str, '%Y-%m-%d') >= cutoff_date
            }
            data['dailyData'] = filtered_daily_data
            daily_data = filtered_daily_data
            print(f"📅 Analyzing last {args.days} days ({len(filtered_daily_data)} days of data)")
        
        has_wellness_data = any(day.get('wellnessMetrics') for day in daily_data.values())
        
        # Run specific analysis based on arguments
        if args.wellness_only:
            if has_wellness_data:
                analyze_wellness_data(daily_data)
            else:
                print(f"🌱 No wellness data found in export.")
        elif args.correlations:
            if has_wellness_data:
                analyze_correlations(daily_data)
            else:
                print(f"🔗 No wellness data found for correlation analysis.")
        else:
            # Full analysis
            analyze_usage_data(data)
            
            if has_wellness_data:
                analyze_wellness_data(daily_data)
                analyze_correlations(daily_data)
            else:
                print(f"\n🌱 No wellness data found in export. Start using the wellness features to see analysis here!")
        
    except FileNotFoundError:
        print(f"Error: File '{args.file}' not found.")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: Invalid JSON file '{args.file}'.")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()