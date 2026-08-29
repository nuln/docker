<?php

namespace App\Providers;

use App\Http\Middleware\DynamicBaseUrl;
use Illuminate\Contracts\Http\Kernel;
use Illuminate\Support\ServiceProvider;

class DynamicBaseUrlServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        $this->app->make(Kernel::class)->pushMiddleware(DynamicBaseUrl::class);
    }
}
