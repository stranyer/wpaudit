import { NextRequest, NextResponse } from 'next/server'

export async function GET(
  request: NextRequest,
  context: { params: Promise<{ testId: string }> }
) {
  const params = await context.params
  return NextResponse.json({ testId: params.testId, works: true })
}

