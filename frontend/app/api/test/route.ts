import { NextResponse } from 'next/server'

export async function GET() {
  return NextResponse.json({ test: 'works', timestamp: new Date().toISOString() })
}

