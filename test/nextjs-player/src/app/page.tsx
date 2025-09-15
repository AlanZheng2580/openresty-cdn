"use client";

import { useEffect, useRef } from 'react';
import Hls from 'hls.js';

const HLSPlayer = () => {
  const videoRef = useRef<HTMLVideoElement>(null);
  // You can change this source to your actual M3U8 file path
  // const src = '/minio/bucket-a/test.m3u8'; 
  const src = 'http://localhost:8080/minio/bucket-a/2024summer/2024summer_nice_song_0/playlist.m3u8';
  const apiKey = '58028419ac995b94cc7750b7c5e3a117';

  useEffect(() => {
    const video = videoRef.current;
    let hls: Hls | null = null;

    if (video) {
      if (Hls.isSupported()) {
        hls = new Hls({
          // Custom XHR setup to add the API Key header
          xhrSetup: (xhr) => {
            xhr.setRequestHeader('X-SECDN-API-KEY', apiKey);
          },
        });
        hls.loadSource(src);
        hls.attachMedia(video);
        hls.on(Hls.Events.MANIFEST_PARSED, () => {
          video.play();
        });
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        // For Safari and other browsers that support HLS natively
        video.src = src;
        video.addEventListener('loadedmetadata', () => {
          video.play();
        });
      }
    }

    // Cleanup on component unmount
    return () => {
      if (hls) {
        hls.destroy();
      }
    };
  }, [src, apiKey]);

  return (
    <div className="w-full max-w-4xl mx-auto">
      <h1 className="text-2xl font-bold text-center my-4">HLS Player Test for OpenResty CDN</h1>
      <video ref={videoRef} controls className="w-full h-auto bg-black" />
      <div className="mt-4 p-4 bg-gray-100 rounded-lg">
        <p className="text-sm text-gray-800">
          <strong>Attempting to load:</strong> <code>{src}</code>
        </p>
        <p className="text-sm text-gray-800">
          <strong>With API Key:</strong> <code>{apiKey}</code>
        </p>
        <p className="mt-2 text-xs text-gray-600">
          If the video does not load, please check the browser's developer console (Network and Console tabs) for CORS or 401 Unauthorized errors.
        </p>
      </div>
    </div>
  );
};


export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center p-8 bg-gray-50">
      <HLSPlayer />
    </main>
  );
}