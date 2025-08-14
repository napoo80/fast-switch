#!/usr/bin/env python3
"""
FastSwitch Usage Data Analyzer

This script analyzes the exported usage data from FastSwitch and generates detailed insights.

USAGE:
    python3 usage_analyzer.py <path_to_exported_json>

EXAMPLES:
    python3 usage_analyzer.py FastSwitch-Usage-Data-2024-08-14.json
    python3 usage_analyzer.py ~/Downloads/usage_data.json --summary

REQUIREMENTS:
    - Python 3.6+
    - JSON file exported from FastSwitch (Menu → Reportes → Exportar Datos)

OUTPUT:
    - Total work time, break time, call time statistics
    - Top applications with usage percentages
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

def main():
    parser = argparse.ArgumentParser(description='Analyze FastSwitch usage data')
    parser.add_argument('file', help='Path to the exported JSON file')
    parser.add_argument('--summary', action='store_true', help='Show summary only')
    
    args = parser.parse_args()
    
    try:
        with open(args.file, 'r') as f:
            data = json.load(f)
        
        analyze_usage_data(data)
        
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