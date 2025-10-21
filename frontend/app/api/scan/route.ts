import { NextRequest, NextResponse } from 'next/server'

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    
    console.log('Proxying scan request to:', `${API_URL}/api/scan`)
    console.log('Request body:', body)
    
    const response = await fetch(`${API_URL}/api/scan`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    })
    
    const data = await response.json()
    
    console.log('API response status:', response.status)
    console.log('API response data:', data)
    
    if (!response.ok) {
      return NextResponse.json(
        { error: data.error || 'Failed to start scan' },
        { status: response.status }
      )
    }
    
    return NextResponse.json(data)
  } catch (error) {
    console.error('Error in scan proxy:', error)
    return NextResponse.json(
      { error: error instanceof Error ? error.message : 'Internal server error' },
      { status: 500 }
    )
  }
}

